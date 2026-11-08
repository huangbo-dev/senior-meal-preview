use std::net::{Ipv4Addr, SocketAddrV4};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port = std::env::var("APP_PORT")
        .unwrap_or_else(|_| "8787".into())
        .parse::<u16>()?;
    if port == 0 {
        return Err("APP_PORT must be between 1 and 65535".into());
    }
    // Intentionally no public/LAN bind option: this unauthenticated prototype is local-only.
    let address = SocketAddrV4::new(Ipv4Addr::LOCALHOST, port);
    let listener = tokio::net::TcpListener::bind(address).await?;
    println!("Illustrative meal-preview API at http://{address} (local-only; no AI model)");
    axum::serve(listener, senior_meal_preview::app())
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
