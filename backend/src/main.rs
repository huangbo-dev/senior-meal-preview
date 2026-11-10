use std::net::{IpAddr, Ipv4Addr, SocketAddr};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port = std::env::var("APP_PORT")
        .unwrap_or_else(|_| "8787".into())
        .parse::<u16>()?;
    if port == 0 {
        return Err("APP_PORT must be between 1 and 65535".into());
    }
    let bind_ip: IpAddr = match std::env::var("APP_BIND_ADDR") {
        Ok(addr) if !addr.trim().is_empty() => addr
            .trim()
            .parse()
            .map_err(|_| "APP_BIND_ADDR must be a valid IPv4 or IPv6 address")?,
        _ => IpAddr::V4(Ipv4Addr::LOCALHOST),
    };
    let config = senior_meal_preview::RuntimeConfig::from_env()?;
    if !bind_ip.is_loopback() && config.api_token.is_none() {
        eprintln!(
            "WARNING: APP_BIND_ADDR={bind_ip} is non-loopback without APP_API_TOKEN. \
             In EC2 production, bind to 127.0.0.1 behind a TLS reverse proxy or set APP_API_TOKEN."
        );
    }

    let address = SocketAddr::new(bind_ip, port);
    let listener = tokio::net::TcpListener::bind(address).await?;
    let worker_desc = match &config.gpu_worker {
        Some(w) => format!(
            "tailscale/remote GPU worker at http://{}:{}{}",
            w.endpoint.host, w.endpoint.port, w.endpoint.path_prefix
        ),
        None => "no GPU worker (illustrative_only)".into(),
    };
    println!("Meal-preview API at http://{address} ({worker_desc})");
    axum::serve(listener, senior_meal_preview::app_with_config(config))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    println!("Meal-preview API stopped.");
    Ok(())
}

/// Resolve on Ctrl-C, or on SIGTERM (sent by systemd, Docker, and `scripts/smoke.py`).
async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
}
