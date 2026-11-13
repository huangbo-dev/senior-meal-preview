//! Stateless meal-preview API with optional Tailscale GPU model-worker bridge for EC2 deployment.
//!
//! By default (`MODEL_WORKER_URL` unset), the service runs in `illustrative_only` mode with zero
//! external network calls. When `MODEL_WORKER_URL` is configured on an EC2 instance joined to a
//! Tailscale tailnet, `render_mode: "gpu_assisted"` requests are validated and forwarded over
//! Tailscale (`100.64.0.0/10` or `*.ts.net`) or loopback to the isolated GPU worker, never
//! silently substituting mock images on failure.

pub mod worker;

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, Request, State, rejection::JsonRejection},
    http::{HeaderMap, HeaderValue, Method, StatusCode, header},
    middleware::Next,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use std::{sync::Arc, sync::LazyLock, time::Duration};
use tower_http::{
    cors::{AllowOrigin, CorsLayer},
    timeout::TimeoutLayer,
};
use worker::{
    GpuArtifact, GpuWorkerConfig, WorkerFailure, WorkerGenerateRequest, WorkerPhotoRequest,
    WorkerTransport,
};

pub const MODE: &str = "illustrative_only";
pub const NOTICE: &str = "Not nutrition, allergen or medical advice.";
/// Fewest and most serving changes a single preview request may contain.
pub const MIN_CHANGES: usize = 1;
pub const MAX_CHANGES: usize = 2;
/// Default upper bound for reading and answering an illustrative request.
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
/// Default timeout for a remote Tailscale GPU worker request.
pub const DEFAULT_GPU_TIMEOUT: Duration = Duration::from_secs(25);

#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub timeout: Duration,
    pub allowed_origins: Vec<String>,
    pub api_token: Option<String>,
    pub gpu_worker: Option<GpuWorkerConfig>,
}

impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            timeout: REQUEST_TIMEOUT,
            allowed_origins: Vec::new(),
            api_token: None,
            gpu_worker: None,
        }
    }
}

impl RuntimeConfig {
    /// Load configuration from environment variables (`APP_ALLOWED_ORIGINS`, `APP_API_TOKEN`,
    /// `MODEL_WORKER_URL`, `MODEL_WORKER_TOKEN`, `MODEL_WORKER_TIMEOUT_MS`,
    /// `MODEL_WORKER_MAX_CONCURRENT`).
    pub fn from_env() -> Result<Self, String> {
        let allowed_origins = std::env::var("APP_ALLOWED_ORIGINS")
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToOwned::to_owned)
            .collect::<Vec<_>>();
        for origin in &allowed_origins {
            if !is_valid_configured_origin(origin) {
                return Err(format!(
                    "Invalid origin '{origin}' in APP_ALLOWED_ORIGINS; use exact http(s)://host[:port]."
                ));
            }
        }
        let api_token = std::env::var("APP_API_TOKEN")
            .ok()
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty());

        let gpu_timeout_ms: u64 = match std::env::var("MODEL_WORKER_TIMEOUT_MS") {
            Ok(v) if !v.trim().is_empty() => v
                .trim()
                .parse()
                .map_err(|_| "MODEL_WORKER_TIMEOUT_MS must be a positive integer.".to_string())?,
            _ => DEFAULT_GPU_TIMEOUT.as_millis() as u64,
        };
        let gpu_max_concurrent: usize = match std::env::var("MODEL_WORKER_MAX_CONCURRENT") {
            Ok(v) if !v.trim().is_empty() => v
                .trim()
                .parse()
                .map_err(|_| "MODEL_WORKER_MAX_CONCURRENT must be between 1 and 16.".to_string())?,
            _ => 2,
        };
        let worker_token = std::env::var("MODEL_WORKER_TOKEN")
            .ok()
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty());

        let gpu_worker = match std::env::var("MODEL_WORKER_URL") {
            Ok(url) if !url.trim().is_empty() => Some(GpuWorkerConfig::new(
                url.trim(),
                worker_token,
                Duration::from_millis(gpu_timeout_ms.max(100)),
                gpu_max_concurrent,
            )?),
            _ => None,
        };

        let request_timeout = match &gpu_worker {
            Some(w) => REQUEST_TIMEOUT.max(w.timeout + Duration::from_secs(2)),
            None => REQUEST_TIMEOUT,
        };

        Ok(Self {
            timeout: request_timeout,
            allowed_origins,
            api_token,
            gpu_worker,
        })
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Dish {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub color: &'static str,
}

#[derive(Debug, Clone, Serialize)]
pub struct Change {
    pub id: &'static str,
    pub label: &'static str,
    pub description: &'static str,
    pub dish_ids: Vec<&'static str>,
}

/// Selection limits enforced by `POST /api/v1/preview`, published so clients do not
/// hard-code them. Additive to schema v1; older clients can ignore it.
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Selection {
    pub min_changes: usize,
    pub max_changes: usize,
}

/// Server-advertised preview capabilities so clients know whether a Tailscale GPU worker
/// is available behind this EC2 gateway.
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Capabilities {
    pub symbolic_preview: bool,
    pub gpu_preview: bool,
    /// `POST /api/v1/photo-preview` can edit a user-taken photo (same readiness probe as
    /// `gpu_preview`). Additive to schema v1.
    pub photo_upload: bool,
}

#[derive(Clone, Serialize)]
pub struct Catalog {
    schema_version: u8,
    mode: &'static str,
    pub dishes: Vec<Dish>,
    pub changes: Vec<Change>,
    pub selection: Selection,
    pub capabilities: Capabilities,
    notice: &'static str,
}

/// The hand-authored catalog, built once and shared by every request.
pub static CATALOG: LazyLock<Catalog> = LazyLock::new(build_catalog);

pub fn catalog() -> &'static Catalog {
    &CATALOG
}

pub fn catalog_for(gpu_enabled: bool) -> Catalog {
    let mut base = CATALOG.clone();
    base.capabilities.gpu_preview = gpu_enabled;
    base
}

fn build_catalog() -> Catalog {
    Catalog {
        schema_version: 1,
        mode: MODE,
        dishes: vec![
            Dish {
                id: "chicken_rice",
                name: "Chicken rice",
                description: "A familiar rice meal",
                color: "#E6AD63",
            },
            Dish {
                id: "fish_soup",
                name: "Fish soup",
                description: "A light soup meal",
                color: "#8DBCC3",
            },
            Dish {
                id: "tofu_rice",
                name: "Tofu rice",
                description: "A plant-based rice meal",
                color: "#A7BA85",
            },
        ],
        changes: vec![
            Change {
                id: "extra_vegetables",
                label: "Add vegetables",
                description: "Extra vegetables on the side",
                dish_ids: vec!["chicken_rice", "fish_soup", "tofu_rice"],
            },
            Change {
                id: "brown_rice",
                label: "Try brown rice",
                description: "Brown rice instead of white rice",
                dish_ids: vec!["chicken_rice", "tofu_rice"],
            },
            Change {
                id: "sauce_on_side",
                label: "Sauce on the side",
                description: "Sauce served separately",
                dish_ids: vec!["chicken_rice", "tofu_rice"],
            },
        ],
        selection: Selection {
            min_changes: MIN_CHANGES,
            max_changes: MAX_CHANGES,
        },
        capabilities: Capabilities {
            symbolic_preview: true,
            gpu_preview: false,
            photo_upload: false,
        },
        notice: NOTICE,
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, Default, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Texture {
    #[default]
    Any,
    Soft,
}

#[derive(Debug, Clone, Deserialize, Serialize, Default, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Flavour {
    #[default]
    Any,
    Mild,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, Default, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RenderMode {
    #[default]
    IllustrativeOnly,
    GpuAssisted,
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(deny_unknown_fields)]
pub struct Preferences {
    #[serde(default)]
    pub texture: Texture,
    #[serde(default)]
    pub flavour: Flavour,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PreviewRequest {
    pub dish_id: String,
    pub change_ids: Vec<String>,
    #[serde(default)]
    pub preferences: Preferences,
    #[serde(default)]
    pub render_mode: RenderMode,
}

#[derive(Debug, Serialize)]
pub struct EditTarget {
    id: &'static str,
    label: &'static str,
    description: &'static str,
}

#[derive(Debug, Serialize)]
pub struct Preview {
    schema_version: u8,
    mode: &'static str,
    dish: Dish,
    edit_targets: Vec<EditTarget>,
    preferences: Preferences,
    summary: String,
    notices: Vec<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gpu_artifact: Option<GpuArtifact>,
}

#[derive(Debug, Serialize)]
pub struct ErrorDetails {
    code: &'static str,
    message: &'static str,
}

#[derive(Debug)]
pub struct ApiError(StatusCode, ErrorDetails);

impl ApiError {
    fn new(status: StatusCode, code: &'static str, message: &'static str) -> Self {
        Self(status, ErrorDetails { code, message })
    }

    fn invalid(code: &'static str, message: &'static str) -> Self {
        Self::new(StatusCode::BAD_REQUEST, code, message)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        #[derive(Serialize)]
        struct ErrorEnvelope {
            error: ErrorDetails,
        }
        (self.0, Json(ErrorEnvelope { error: self.1 })).into_response()
    }
}

pub fn make_preview(request: PreviewRequest) -> Result<Preview, ApiError> {
    let catalog = catalog();
    let dish = catalog
        .dishes
        .iter()
        .find(|dish| dish.id == request.dish_id)
        .cloned()
        .ok_or_else(|| ApiError::invalid("unknown_dish", "Choose a meal from the catalog."))?;
    if !(MIN_CHANGES..=MAX_CHANGES).contains(&request.change_ids.len()) {
        return Err(ApiError::invalid(
            "change_count",
            "Choose one or two meal changes.",
        ));
    }
    let ids = &request.change_ids;
    if ids
        .iter()
        .enumerate()
        .any(|(index, id)| ids[..index].contains(id))
    {
        return Err(ApiError::invalid(
            "duplicate_change",
            "Choose different meal changes.",
        ));
    }
    let mut targets = Vec::with_capacity(MAX_CHANGES);
    for id in request.change_ids {
        let change = catalog
            .changes
            .iter()
            .find(|change| change.id == id)
            .ok_or_else(|| {
                ApiError::invalid("unknown_change", "Choose changes from the catalog.")
            })?;
        if !change.dish_ids.contains(&dish.id) {
            return Err(ApiError::invalid(
                "incompatible_change",
                "That change is not available for this meal.",
            ));
        }
        targets.push(EditTarget {
            id: change.id,
            label: change.label,
            description: change.description,
        });
    }
    let names: Vec<_> = targets.iter().map(|target| target.label).collect();
    let summary = format!("{}: {}.", dish.name, names.join(" and "));
    let mut notices = vec![
        NOTICE,
        "No picture was generated. Your choices are not saved.",
    ];
    if request.preferences.texture == Texture::Soft {
        notices.push("Soft is a preference, not a check of swallowing safety. Follow your clinician's advice.");
    }
    Ok(Preview {
        schema_version: 1,
        mode: MODE,
        dish,
        edit_targets: targets,
        preferences: request.preferences,
        summary,
        notices,
        gpu_artifact: None,
    })
}

/// Plain-language API error for a GPU worker failure. Never substitutes a mock image.
fn worker_error(failure: WorkerFailure) -> ApiError {
    match failure {
        WorkerFailure::Busy => ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "gpu_busy",
            "The GPU model worker is busy with another request. Please try again or use symbolic illustration.",
        ),
        WorkerFailure::Timeout => ApiError::new(
            StatusCode::GATEWAY_TIMEOUT,
            "gpu_timeout",
            "The Tailscale GPU model worker timed out. Check the GPU node or use symbolic illustration.",
        ),
        WorkerFailure::Unsupported => ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "gpu_unsupported_request",
            "The AI preview currently handles one change at a time: brown rice or added vegetables on a rice meal. Choose one of those, or use symbolic illustration.",
        ),
        WorkerFailure::NotReady => ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "gpu_not_ready",
            "The GPU model worker is running but its models or meal photos are not ready. No mock image was substituted. Use symbolic illustration for now.",
        ),
        WorkerFailure::Unreachable(_) => ApiError::new(
            StatusCode::BAD_GATEWAY,
            "gpu_unreachable",
            "Cannot reach the GPU model worker over Tailscale. Verify tailscaled and the worker service.",
        ),
        WorkerFailure::InvalidResponse(_) => ApiError::new(
            StatusCode::BAD_GATEWAY,
            "gpu_invalid_response",
            "The GPU model worker returned an invalid response. No mock image was substituted.",
        ),
        WorkerFailure::BadPhoto => ApiError::new(
            StatusCode::BAD_REQUEST,
            "photo_invalid",
            "The photo or the painted area could not be used. Paint over the rice only, then try again.",
        ),
    }
}

async fn preview(
    State(config): State<Arc<RuntimeConfig>>,
    body: Result<Json<PreviewRequest>, JsonRejection>,
) -> Result<Json<Preview>, ApiError> {
    let Json(request) = body.map_err(|error| {
        let (status, code, message) = match error.status() {
            StatusCode::PAYLOAD_TOO_LARGE => (
                StatusCode::PAYLOAD_TOO_LARGE,
                "body_too_large",
                "The request is too large.",
            ),
            StatusCode::UNSUPPORTED_MEDIA_TYPE => (
                StatusCode::UNSUPPORTED_MEDIA_TYPE,
                "content_type",
                "Send an application/json request.",
            ),
            _ => (
                StatusCode::UNPROCESSABLE_ENTITY,
                "invalid_json",
                "The request does not match the supported meal-preview format.",
            ),
        };
        ApiError::new(status, code, message)
    })?;

    let render_mode = request.render_mode;
    let worker_req = WorkerGenerateRequest {
        schema_version: 1,
        dish_id: request.dish_id.clone(),
        change_ids: request.change_ids.clone(),
        texture: request.preferences.texture.clone(),
        flavour: request.preferences.flavour.clone(),
    };
    let mut result = make_preview(request)?;

    if render_mode == RenderMode::GpuAssisted {
        let Some(ref worker_cfg) = config.gpu_worker else {
            return Err(ApiError::new(
                StatusCode::SERVICE_UNAVAILABLE,
                "gpu_unavailable",
                "The Tailscale GPU model worker is not configured on this server. Switch to symbolic illustration or start the worker.",
            ));
        };
        let artifact = worker::request_gpu_preview(worker_cfg, &worker_req)
            .await
            .map_err(worker_error)?;
        // Replace the no-AI-model notice with the truthful GPU-worker provenance notice.
        result.notices[1] =
            "AI-generated from a stock meal photo, not a real meal. Your choices are not saved.";
        result
            .notices
            .push("The automated check is not human or clinical verification.");
        result.gpu_artifact = Some(artifact);
    }

    Ok(Json(result))
}

fn local_web_origin(origin: &HeaderValue) -> bool {
    let Ok(value) = origin.to_str() else {
        return false;
    };
    // Origin must be exactly a loopback HTTP origin, never a URL path or lookalike host.
    let Some(authority) = value.strip_prefix("http://") else {
        return false;
    };
    let (host, port) = authority.rsplit_once(':').unwrap_or((authority, "80"));
    matches!(host, "localhost" | "127.0.0.1") && port.parse::<u16>().is_ok_and(|p| p > 0)
}

fn is_valid_configured_origin(origin: &str) -> bool {
    let Some(authority) = origin
        .strip_prefix("https://")
        .or_else(|| origin.strip_prefix("http://"))
    else {
        return false;
    };
    if authority.is_empty() || authority.contains(['/', '?', '#', '@', ' ']) {
        return false;
    }
    let (host, port) = authority.rsplit_once(':').unwrap_or((authority, "443"));
    !host.is_empty() && port.parse::<u16>().is_ok_and(|p| p > 0)
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (&x, &y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

async fn require_api_token(
    State(config): State<Arc<RuntimeConfig>>,
    headers: HeaderMap,
    request: Request,
    next: Next,
) -> Result<Response, ApiError> {
    if request.method() != Method::OPTIONS
        && let Some(ref expected) = config.api_token
    {
        let provided = headers
            .get(header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .map(str::trim);
        match provided {
            Some(token) if constant_time_eq(token.as_bytes(), expected.as_bytes()) => {}
            _ => {
                return Err(ApiError::new(
                    StatusCode::UNAUTHORIZED,
                    "unauthorized",
                    "Missing or invalid API bearer token.",
                ));
            }
        }
    }
    Ok(next.run(request).await)
}

/// Largest request body accepted by `POST /api/v1/photo-preview` (two base64 PNGs).
pub const MAX_PHOTO_BODY_BYTES: usize = 8 * 1024 * 1024;
/// Largest single base64 image in a photo request.
const MAX_PHOTO_B64_CHARS: usize = 6 * 1024 * 1024;
/// Base64 of the 8-byte PNG signature.
const PNG_B64_PREFIX: &str = "iVBORw0KGgo";
/// Changes the model was evaluated on, the only ones offered for a user photo.
pub const PHOTO_CHANGE_IDS: [&str; 2] = ["brown_rice", "extra_vegetables"];

/// A user-taken photo plus the painted area to change. Unknown fields are rejected.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PhotoPreviewRequest {
    pub change_id: String,
    pub image_png_base64: String,
    pub mask_png_base64: String,
}

#[derive(Debug, Serialize)]
pub struct PhotoPreview {
    schema_version: u8,
    edit_target: EditTarget,
    notices: Vec<&'static str>,
    pub gpu_artifact: GpuArtifact,
}

fn looks_like_png_base64(value: &str) -> bool {
    value.len() <= MAX_PHOTO_B64_CHARS
        && value.len().is_multiple_of(4)
        && value.starts_with(PNG_B64_PREFIX)
        && value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'='))
}

async fn photo_preview(
    State(config): State<Arc<RuntimeConfig>>,
    body: Result<Json<PhotoPreviewRequest>, JsonRejection>,
) -> Result<Json<PhotoPreview>, ApiError> {
    let Json(request) = body.map_err(|error| match error.status() {
        StatusCode::PAYLOAD_TOO_LARGE => ApiError::new(
            StatusCode::PAYLOAD_TOO_LARGE,
            "body_too_large",
            "The photo is too large.",
        ),
        StatusCode::UNSUPPORTED_MEDIA_TYPE => ApiError::new(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            "content_type",
            "Send an application/json request.",
        ),
        _ => ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "invalid_json",
            "The request does not match the photo-preview format.",
        ),
    })?;
    if !PHOTO_CHANGE_IDS.contains(&request.change_id.as_str()) {
        return Err(ApiError::invalid(
            "unsupported_change",
            "For your own photo, choose brown rice or added vegetables.",
        ));
    }
    if !looks_like_png_base64(&request.image_png_base64)
        || !looks_like_png_base64(&request.mask_png_base64)
    {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "photo_invalid",
            "The photo or the painted area could not be used. Paint over the rice only, then try again.",
        ));
    }
    let change = CATALOG
        .changes
        .iter()
        .find(|c| c.id == request.change_id)
        .expect("photo change ids are catalog changes");
    let Some(ref worker_cfg) = config.gpu_worker else {
        return Err(ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "gpu_unavailable",
            "Photo editing is not switched on for this server right now.",
        ));
    };
    let payload = WorkerPhotoRequest {
        schema_version: 1,
        change_id: request.change_id,
        image_png_base64: request.image_png_base64,
        mask_png_base64: request.mask_png_base64,
    };
    let artifact = worker::request_gpu_photo_edit(worker_cfg, &payload)
        .await
        .map_err(worker_error)?;
    Ok(Json(PhotoPreview {
        schema_version: 1,
        edit_target: EditTarget {
            id: change.id,
            label: change.label,
            description: change.description,
        },
        notices: vec![
            "Experimental AI edit of your photo. No person has checked it.",
            "Your photo is deleted after the edit and is not saved.",
            NOTICE,
        ],
        gpu_artifact: artifact,
    }))
}

pub fn app() -> Router {
    app_with_config(RuntimeConfig::default())
}

/// Same router as [`app`], with an explicit request timeout (used by tests).
pub fn app_with_timeout(timeout: Duration) -> Router {
    app_with_config(RuntimeConfig {
        timeout,
        ..RuntimeConfig::default()
    })
}

/// Build the router with explicit EC2 / Tailscale GPU worker configuration.
pub fn app_with_config(config: RuntimeConfig) -> Router {
    let timeout = config.timeout;
    let allowed_origins = Arc::new(config.allowed_origins.clone());
    let shared = Arc::new(config);

    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate({
            let allowed_origins = Arc::clone(&allowed_origins);
            move |origin: &HeaderValue, _| {
                local_web_origin(origin)
                    || origin
                        .to_str()
                        .is_ok_and(|value| allowed_origins.iter().any(|o| o == value))
            }
        }))
        .allow_methods([Method::GET, Method::POST])
        .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION]);

    let api_routes = Router::new()
        .route(
            "/api/v1/catalog",
            get(|State(cfg): State<Arc<RuntimeConfig>>| async move {
                let ready = match cfg.gpu_worker.as_ref() {
                    Some(worker) => worker::worker_readiness(worker).await,
                    None => worker::WorkerReadiness::default(),
                };
                let mut catalog = catalog_for(ready.gpu_preview);
                catalog.capabilities.photo_upload = ready.photo_upload;
                Json(catalog)
            }),
        )
        .route("/api/v1/preview", post(preview))
        .route(
            "/api/v1/photo-preview",
            post(photo_preview).layer(DefaultBodyLimit::max(MAX_PHOTO_BODY_BYTES)),
        )
        .route_layer(axum::middleware::from_fn_with_state(
            Arc::clone(&shared),
            require_api_token,
        ));

    Router::new()
        .route(
            "/healthz",
            get(|State(cfg): State<Arc<RuntimeConfig>>| async move {
                let (configured, transport) = match cfg.gpu_worker {
                    Some(ref w) => (true, w.endpoint.transport),
                    None => (false, WorkerTransport::None),
                };
                Json(Health {
                    status: "ok",
                    mode: MODE,
                    gpu_worker: GpuWorkerHealth {
                        configured,
                        transport,
                    },
                })
            }),
        )
        .merge(api_routes)
        .fallback(|| async {
            ApiError::new(
                StatusCode::NOT_FOUND,
                "not_found",
                "This API route does not exist.",
            )
        })
        .method_not_allowed_fallback(|| async {
            ApiError::new(
                StatusCode::METHOD_NOT_ALLOWED,
                "method_not_allowed",
                "This method is not supported for this route.",
            )
        })
        .with_state(shared)
        .layer(DefaultBodyLimit::max(16 * 1024))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            timeout,
        ))
        .layer(cors)
        .layer(axum::middleware::map_response(
            |response: Response| async move {
                // No handler returns 408 itself; it only comes from the timeout layer, whose
                // body is empty. Give clients the same structured error shape as other failures.
                let mut response = if response.status() == StatusCode::REQUEST_TIMEOUT {
                    ApiError::new(
                        StatusCode::REQUEST_TIMEOUT,
                        "timeout",
                        "The request took too long. Please try again.",
                    )
                    .into_response()
                } else {
                    response
                };
                response
                    .headers_mut()
                    .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
                response.headers_mut().insert(
                    header::X_CONTENT_TYPE_OPTIONS,
                    HeaderValue::from_static("nosniff"),
                );
                response
            },
        ))
}

#[derive(Serialize)]
struct GpuWorkerHealth {
    configured: bool,
    transport: WorkerTransport,
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
    mode: &'static str,
    gpu_worker: GpuWorkerHealth,
}
