//! Tailscale GPU model-worker client and SSRF/network boundary checks for EC2 deployment.
//!
//! When the Rust API runs on an EC2 instance and the diffusion/checker pipeline runs on a
//! separate GPU machine joined to the same Tailscale tailnet (`tailscale0`), this module
//! validates that the worker URL is strictly on Tailscale (`100.64.0.0/10`,
//! `fd7a:115c:a1e0::/48`, or `*.ts.net`) or loopback (`127.0.0.1` / `localhost`), blocks
//! EC2 IMDS (`169.254.169.254`) and arbitrary hosts, enforces bounded concurrency, and
//! forwards only validated catalog IDs and preferences.

use serde::{Deserialize, Serialize};
use std::{
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    sync::Arc,
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    sync::Semaphore,
};

use crate::{Flavour, Texture};

/// Max response size accepted from the GPU worker (4 MiB, enough for a preview PNG data URL).
const MAX_WORKER_RESPONSE_BYTES: usize = 4 * 1024 * 1024;

/// How the EC2 gateway reaches the GPU worker.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkerTransport {
    None,
    Loopback,
    Tailscale,
}

/// Validated target endpoint for the GPU model worker.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkerEndpoint {
    pub host: String,
    pub port: u16,
    pub path_prefix: String,
    pub transport: WorkerTransport,
}

/// Configuration for the remote GPU worker behind Tailscale.
#[derive(Debug, Clone)]
pub struct GpuWorkerConfig {
    pub endpoint: WorkerEndpoint,
    pub bearer_token: Option<String>,
    pub timeout: Duration,
    pub max_concurrent: usize,
    semaphore: Arc<Semaphore>,
}

impl GpuWorkerConfig {
    pub fn new(
        url: &str,
        bearer_token: Option<String>,
        timeout: Duration,
        max_concurrent: usize,
    ) -> Result<Self, String> {
        let endpoint = validate_worker_url(url)?;
        let max_concurrent = max_concurrent.clamp(1, 16);
        if let Some(ref token) = bearer_token
            && (token.trim().is_empty() || token.bytes().any(|b| !(0x21..=0x7e).contains(&b)))
        {
            return Err("MODEL_WORKER_TOKEN must contain non-whitespace ASCII characters.".into());
        }
        Ok(Self {
            endpoint,
            bearer_token,
            timeout,
            max_concurrent,
            semaphore: Arc::new(Semaphore::new(max_concurrent)),
        })
    }
}

/// Request sent from the EC2 Rust backend to `<MODEL_WORKER_URL>/v1/generate`.
/// Never carries arbitrary prompts, file paths, or user-uploaded photos.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkerGenerateRequest {
    pub schema_version: u8,
    pub dish_id: String,
    pub change_ids: Vec<String>,
    pub texture: Texture,
    pub flavour: Flavour,
}

/// Provenance and output returned by the GPU worker and forwarded to the client.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct GpuArtifact {
    /// E.g. `"tailscale-gpu-worker"` or `"tailscale-gpu-dry-run"`.
    pub provider: String,
    /// E.g. `"brushnet-sdxl+qwen2.5-vl-7b-4bit"` or `"dry_run_fixture"`.
    pub model: String,
    /// Locked prompt template identifier selected by the worker.
    pub prompt_id: String,
    /// Deterministic seed used by the worker.
    pub seed: u64,
    /// Number of check-and-retry attempts used (1..=8).
    pub attempts: u8,
    /// Whether the VLM checker marked the candidate as passing selection criteria.
    /// Reported for provenance only, never as human ground truth.
    pub checker_passed: bool,
    /// Base64 `data:image/png;base64,...` preview image returned by the worker.
    pub image_data_url: String,
    /// Mandatory disclosure attached to every generated artifact.
    pub generated_label: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkerFailure {
    Busy,
    Timeout,
    /// The worker is reachable but has no validated model path for this request (HTTP 422).
    Unsupported,
    /// The worker is reachable but its models, fixtures or checker are not ready (HTTP 503).
    NotReady,
    Unreachable(String),
    InvalidResponse(String),
}

/// True if `ip` is in the Tailscale CGNAT IPv4 range (`100.64.0.0/10`).
pub fn is_tailscale_ipv4(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    octets[0] == 100 && (64..=127).contains(&octets[1])
}

/// True if `ip` is in the Tailscale ULA IPv6 prefix (`fd7a:115c:a1e0::/48`).
pub fn is_tailscale_ipv6(ip: Ipv6Addr) -> bool {
    let segments = ip.segments();
    segments[0] == 0xfd7a && segments[1] == 0x115c && segments[2] == 0xa1e0
}

/// Classify an IP address as loopback, Tailscale, or forbidden (including EC2 IMDS `169.254.169.254`).
pub fn classify_worker_ip(ip: IpAddr) -> Option<WorkerTransport> {
    match ip {
        IpAddr::V4(v4) if v4.is_loopback() => Some(WorkerTransport::Loopback),
        IpAddr::V4(v4) if is_tailscale_ipv4(v4) => Some(WorkerTransport::Tailscale),
        IpAddr::V6(v6) if v6.is_loopback() => Some(WorkerTransport::Loopback),
        IpAddr::V6(v6) if is_tailscale_ipv6(v6) => Some(WorkerTransport::Tailscale),
        _ => None,
    }
}

fn is_valid_ts_net_hostname(host: &str) -> bool {
    let host = host.to_ascii_lowercase();
    let Some(prefix) = host.strip_suffix(".ts.net") else {
        return false;
    };
    !prefix.is_empty()
        && prefix.split('.').all(|label| {
            !label.is_empty()
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-')
        })
}

/// Parse and validate `MODEL_WORKER_URL`.
///
/// Only `http://` over Tailscale (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`, `*.ts.net`) or
/// loopback (`127.0.0.1`, `localhost`) is permitted. Public hosts, RFC1918 LAN IPs, and
/// AWS IMDS (`169.254.169.254`) are rejected.
pub fn validate_worker_url(raw: &str) -> Result<WorkerEndpoint, String> {
    let trimmed = raw.trim().trim_end_matches('/');
    let Some(rest) = trimmed.strip_prefix("http://") else {
        return Err(
            "MODEL_WORKER_URL must start with http:// (encrypted over the tailscale0 tunnel or loopback)."
                .into(),
        );
    };
    if rest.contains(['?', '#', '@', ' ', '\t', '\r', '\n']) {
        return Err(
            "MODEL_WORKER_URL must not contain credentials, query strings, or fragments.".into(),
        );
    }
    let (authority, path_part) = match rest.split_once('/') {
        Some((a, p)) => (a, format!("/{}", p.trim_matches('/'))),
        None => (rest, String::new()),
    };
    if path_part.contains("..") {
        return Err("MODEL_WORKER_URL path must not contain '..'.".into());
    }
    let (host, port_str) = if let Some(bracketed) = authority.strip_prefix('[') {
        let Some((ipv6_host, remainder)) = bracketed.split_once(']') else {
            return Err("Invalid IPv6 address in MODEL_WORKER_URL.".into());
        };
        let port = remainder.strip_prefix(':').unwrap_or("8790");
        (ipv6_host.to_string(), port)
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) => (h.to_string(), p),
            None => (authority.to_string(), "8790"),
        }
    };
    let port: u16 = port_str
        .parse()
        .ok()
        .filter(|&p| p > 0)
        .ok_or_else(|| "MODEL_WORKER_URL port must be between 1 and 65535.".to_string())?;

    let transport = if host.eq_ignore_ascii_case("localhost") {
        WorkerTransport::Loopback
    } else if let Ok(ip) = host.parse::<IpAddr>() {
        classify_worker_ip(ip).ok_or_else(|| {
            format!(
                "MODEL_WORKER_URL IP {ip} is not allowed; use a Tailscale IP (100.64.0.0/10) or loopback (127.0.0.1)."
            )
        })?
    } else if is_valid_ts_net_hostname(&host) {
        WorkerTransport::Tailscale
    } else {
        return Err(format!(
            "MODEL_WORKER_URL host '{host}' is not allowed; use a Tailscale IP (100.64.0.0/10), *.ts.net MagicDNS host, or 127.0.0.1."
        ));
    };

    Ok(WorkerEndpoint {
        host,
        port,
        path_prefix: if path_part == "/" {
            String::new()
        } else {
            path_part
        },
        transport,
    })
}

/// Probe worker configuration readiness, never infer it from a configured URL alone.
/// Dry-run, legacy/malformed replies and failures all fail closed. This does not
/// certify visual quality, model correctness or readiness for every catalog item.
pub async fn gpu_preview_ready(config: &GpuWorkerConfig) -> bool {
    tokio::time::timeout(
        config.timeout.min(Duration::from_secs(1)),
        read_worker_readiness(config),
    )
    .await
    .ok()
    .and_then(Result::ok)
    .unwrap_or(false)
}

async fn read_worker_readiness(config: &GpuWorkerConfig) -> Result<bool, WorkerFailure> {
    let addr = resolve_verified_addr(&config.endpoint).await?;
    let mut stream = TcpStream::connect(addr)
        .await
        .map_err(|e| WorkerFailure::Unreachable(e.to_string()))?;
    let auth = config
        .bearer_token
        .as_ref()
        .map(|token| format!("Authorization: Bearer {token}\r\n"))
        .unwrap_or_default();
    let request = format!(
        "GET {}/healthz HTTP/1.1\r\nHost: {}:{}\r\nAccept: application/json\r\nConnection: close\r\n{}\r\n",
        config.endpoint.path_prefix, config.endpoint.host, config.endpoint.port, auth
    );
    stream
        .write_all(request.as_bytes())
        .await
        .map_err(|e| WorkerFailure::Unreachable(e.to_string()))?;
    // Health payloads are tiny. Bound both bytes and wall time, independent of generation.
    let mut bytes = Vec::new();
    stream
        .take(16_385)
        .read_to_end(&mut bytes)
        .await
        .map_err(|e| WorkerFailure::Unreachable(e.to_string()))?;
    if bytes.len() > 16_384 {
        return Ok(false);
    }
    let Some(end) = bytes.windows(4).position(|w| w == b"\r\n\r\n") else {
        return Ok(false);
    };
    let head = String::from_utf8_lossy(&bytes[..end]);
    if head
        .lines()
        .next()
        .and_then(|s| s.split_whitespace().nth(1))
        != Some("200")
    {
        return Ok(false);
    }
    #[derive(Deserialize)]
    struct Readiness {
        status: String,
        worker_mode: String,
        gpu_ready: bool,
    }
    let Ok(health) = serde_json::from_slice::<Readiness>(&bytes[end + 4..]) else {
        return Ok(false);
    };
    Ok(health.status == "ok" && health.worker_mode == "gpu" && health.gpu_ready)
}

/// Call the remote GPU worker over Tailscale or loopback.
pub async fn request_gpu_preview(
    config: &GpuWorkerConfig,
    payload: &WorkerGenerateRequest,
) -> Result<GpuArtifact, WorkerFailure> {
    let _permit = config
        .semaphore
        .clone()
        .try_acquire_owned()
        .map_err(|_| WorkerFailure::Busy)?;

    tokio::time::timeout(config.timeout, send_worker_http(config, payload))
        .await
        .map_err(|_| WorkerFailure::Timeout)?
}

async fn resolve_verified_addr(endpoint: &WorkerEndpoint) -> Result<SocketAddr, WorkerFailure> {
    if let Ok(ip) = endpoint.host.parse::<IpAddr>() {
        if classify_worker_ip(ip).is_none() {
            return Err(WorkerFailure::Unreachable(
                "Worker IP failed Tailscale/loopback boundary check.".into(),
            ));
        }
        return Ok(SocketAddr::new(ip, endpoint.port));
    }
    let addrs = tokio::net::lookup_host((endpoint.host.as_str(), endpoint.port))
        .await
        .map_err(|e| WorkerFailure::Unreachable(format!("Cannot resolve worker host: {e}")))?;
    for addr in addrs {
        if let Some(actual) = classify_worker_ip(addr.ip())
            && (endpoint.transport == WorkerTransport::Loopback
                || actual == WorkerTransport::Tailscale)
        {
            return Ok(addr);
        }
    }
    Err(WorkerFailure::Unreachable(
        "Resolved worker address is outside the allowed Tailscale/loopback range.".into(),
    ))
}

async fn send_worker_http(
    config: &GpuWorkerConfig,
    payload: &WorkerGenerateRequest,
) -> Result<GpuArtifact, WorkerFailure> {
    let addr = resolve_verified_addr(&config.endpoint).await?;
    let mut stream = TcpStream::connect(addr)
        .await
        .map_err(|e| WorkerFailure::Unreachable(format!("Cannot connect to GPU worker: {e}")))?;

    let body = serde_json::to_vec(payload)
        .map_err(|e| WorkerFailure::InvalidResponse(format!("Cannot encode request: {e}")))?;
    let path = format!("{}/v1/generate", config.endpoint.path_prefix);
    let auth_header = match config.bearer_token {
        Some(ref token) => format!("Authorization: Bearer {token}\r\n"),
        None => String::new(),
    };
    let request_head = format!(
        "POST {path} HTTP/1.1\r\n\
         Host: {}:{}\r\n\
         Content-Type: application/json\r\n\
         Accept: application/json\r\n\
         Connection: close\r\n\
         {auth_header}\
         Content-Length: {}\r\n\r\n",
        config.endpoint.host,
        config.endpoint.port,
        body.len()
    );

    let mut request_bytes = request_head.into_bytes();
    request_bytes.extend_from_slice(&body);

    stream
        .write_all(&request_bytes)
        .await
        .map_err(|e| WorkerFailure::Unreachable(format!("Failed writing to GPU worker: {e}")))?;
    stream
        .flush()
        .await
        .map_err(|e| WorkerFailure::Unreachable(format!("Failed flushing worker stream: {e}")))?;

    let mut response_bytes = Vec::new();
    stream
        .take((MAX_WORKER_RESPONSE_BYTES + 1) as u64)
        .read_to_end(&mut response_bytes)
        .await
        .map_err(|e| WorkerFailure::Unreachable(format!("Failed reading worker response: {e}")))?;
    if response_bytes.len() > MAX_WORKER_RESPONSE_BYTES {
        return Err(WorkerFailure::InvalidResponse(
            "GPU worker response exceeded 4 MiB limit.".into(),
        ));
    }

    let Some(header_end) = response_bytes.windows(4).position(|w| w == b"\r\n\r\n") else {
        return Err(WorkerFailure::InvalidResponse(
            "Malformed HTTP response from GPU worker.".into(),
        ));
    };
    let header_str = std::str::from_utf8(&response_bytes[..header_end])
        .map_err(|_| WorkerFailure::InvalidResponse("Non-UTF8 worker HTTP headers.".into()))?;
    let status_line = header_str.lines().next().unwrap_or_default();
    let status_code: u16 = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| WorkerFailure::InvalidResponse("Missing HTTP status from worker.".into()))?;

    let json_slice = &response_bytes[header_end + 4..];
    match status_code {
        200..300 => {}
        422 => return Err(WorkerFailure::Unsupported),
        503 => return Err(WorkerFailure::NotReady),
        _ => {
            return Err(WorkerFailure::Unreachable(format!(
                "GPU worker returned HTTP {status_code}."
            )));
        }
    }
    let artifact: GpuArtifact = serde_json::from_slice(json_slice)
        .map_err(|e| WorkerFailure::InvalidResponse(format!("Invalid worker JSON schema: {e}")))?;
    validate_gpu_artifact(&artifact)?;
    Ok(artifact)
}

fn validate_gpu_artifact(artifact: &GpuArtifact) -> Result<(), WorkerFailure> {
    if artifact.provider.trim().is_empty()
        || artifact.model.trim().is_empty()
        || artifact.prompt_id.trim().is_empty()
        || !(1..=8).contains(&artifact.attempts)
        || !artifact
            .image_data_url
            .starts_with("data:image/png;base64,")
        || artifact.image_data_url.len() < 32
        || !artifact
            .generated_label
            .to_ascii_lowercase()
            .contains("not")
    {
        return Err(WorkerFailure::InvalidResponse(
            "GPU worker artifact failed provenance or image format validation.".into(),
        ));
    }
    Ok(())
}
