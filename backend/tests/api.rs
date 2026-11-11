use axum::{
    body::Body,
    http::{Method, Request, StatusCode, header},
};
use http_body_util::BodyExt;
use serde_json::{Value, json};
use tower::ServiceExt;

async fn call(method: Method, path: &str, body: Value) -> (StatusCode, Value) {
    let response = senior_meal_preview::app()
        .oneshot(
            Request::builder()
                .method(method)
                .uri(path)
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
    assert_eq!(
        response.headers()[header::X_CONTENT_TYPE_OPTIONS],
        "nosniff"
    );
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

fn request() -> Value {
    json!({"dish_id":"chicken_rice","change_ids":["brown_rice","extra_vegetables"],"preferences":{"texture":"soft","flavour":"mild"}})
}

#[tokio::test]
async fn health_and_catalog_are_explicitly_illustrative() {
    let (status, health) = call(Method::GET, "/healthz", Value::Null).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(health["mode"], "illustrative_only");
    let (status, catalog) = call(Method::GET, "/api/v1/catalog", Value::Null).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(catalog["schema_version"], 1);
    assert_eq!(catalog["dishes"].as_array().unwrap().len(), 3);
    assert_eq!(catalog["changes"].as_array().unwrap().len(), 3);
    assert!(
        catalog["notice"]
            .as_str()
            .unwrap()
            .contains("Not nutrition")
    );
}

#[tokio::test]
async fn valid_preview_preserves_targets_and_preferences() {
    let (status, value) = call(Method::POST, "/api/v1/preview", request()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(value["mode"], "illustrative_only");
    assert_eq!(value["edit_targets"][0]["id"], "brown_rice");
    assert_eq!(value["edit_targets"][1]["id"], "extra_vegetables");
    assert_eq!(value["preferences"]["texture"], "soft");
    assert_eq!(value["preferences"]["flavour"], "mild");
    assert!(
        value["notices"]
            .as_array()
            .unwrap()
            .iter()
            .any(|n| n.as_str().unwrap().contains("swallowing safety"))
    );
    assert!(value.get("image_url").is_none());
    assert!(value.get("nutrition").is_none());
}

#[tokio::test]
async fn optional_preferences_default_to_any() {
    let (status, value) = call(
        Method::POST,
        "/api/v1/preview",
        json!({"dish_id":"fish_soup","change_ids":["extra_vegetables"]}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        value["preferences"],
        json!({"texture":"any","flavour":"any"})
    );
}

#[tokio::test]
async fn invalid_selections_are_rejected_with_stable_codes() {
    let cases = [
        (
            json!({"dish_id":"unknown","change_ids":["brown_rice"]}),
            "unknown_dish",
        ),
        (
            json!({"dish_id":"chicken_rice","change_ids":[]}),
            "change_count",
        ),
        (
            json!({"dish_id":"chicken_rice","change_ids":["brown_rice","extra_vegetables","sauce_on_side"]}),
            "change_count",
        ),
        (
            json!({"dish_id":"chicken_rice","change_ids":["brown_rice","brown_rice"]}),
            "duplicate_change",
        ),
        (
            json!({"dish_id":"chicken_rice","change_ids":["magic"]}),
            "unknown_change",
        ),
        (
            json!({"dish_id":"fish_soup","change_ids":["brown_rice"]}),
            "incompatible_change",
        ),
        (
            json!({"dish_id":"fish_soup","change_ids":["sauce_on_side"]}),
            "incompatible_change",
        ),
    ];
    for (body, code) in cases {
        let (status, result) = call(Method::POST, "/api/v1/preview", body).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{code}");
        assert_eq!(result["error"]["code"], code);
    }
}

#[tokio::test]
async fn every_supported_dish_change_pair_works() {
    let (_, catalog) = call(Method::GET, "/api/v1/catalog", Value::Null).await;
    for change in catalog["changes"].as_array().unwrap() {
        for dish_id in change["dish_ids"].as_array().unwrap() {
            let (status, value) = call(
                Method::POST,
                "/api/v1/preview",
                json!({"dish_id":dish_id,"change_ids":[change["id"]]}),
            )
            .await;
            assert_eq!(status, StatusCode::OK);
            assert_eq!(value["dish"]["id"], *dish_id);
        }
    }
}

#[tokio::test]
async fn unknown_fields_and_preference_values_are_rejected() {
    let mut bodies = Vec::new();
    let mut extra = request();
    extra["photo"] = json!("data:image/png;base64,not-supported");
    bodies.push(extra);
    let mut extra = request();
    extra["preferences"]["health_condition"] = json!("not-collected");
    bodies.push(extra);
    let mut extra = request();
    extra["preferences"]["texture"] = json!("clinical-diet");
    bodies.push(extra);
    let mut extra = request();
    extra["preferences"]["flavour"] = json!("anything-else");
    bodies.push(extra);
    bodies.extend([
        json!({}),
        Value::Null,
        json!([]),
        json!({"dish_id":42,"change_ids":[]}),
    ]);
    for body in bodies {
        let (status, value) = call(Method::POST, "/api/v1/preview", body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(value["error"]["code"], "invalid_json");
    }
}

#[tokio::test]
async fn malformed_json_and_wrong_content_type_return_json_errors() {
    for (content_type, body, expected_status) in [
        ("application/json", "{", StatusCode::UNPROCESSABLE_ENTITY),
        ("text/plain", "{}", StatusCode::UNSUPPORTED_MEDIA_TYPE),
    ] {
        let response = senior_meal_preview::app()
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/api/v1/preview")
                    .header(header::CONTENT_TYPE, content_type)
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), expected_status);
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        assert!(value["error"]["message"].is_string());
    }
}

#[tokio::test]
async fn oversized_body_is_rejected() {
    let response = senior_meal_preview::app()
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/api/v1/preview")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(" ".repeat(20_000)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn cors_allows_only_exact_loopback_http_origins() {
    for (origin, allowed) in [
        ("http://localhost:5173", true),
        ("http://127.0.0.1:8080", true),
        ("http://localhost", true),
        ("https://localhost:8080", false),
        ("https://example.com", false),
        ("null", false),
        ("http://localhost.evil.test:8080", false),
        ("http://127.0.0.1.evil.test:8080", false),
        ("http://localhost:8080/evil", false),
        ("http://localhost:0", false),
    ] {
        let response = senior_meal_preview::app()
            .oneshot(
                Request::builder()
                    .method(Method::OPTIONS)
                    .uri("/api/v1/preview")
                    .header(header::ORIGIN, origin)
                    .header(header::ACCESS_CONTROL_REQUEST_METHOD, "POST")
                    .header(header::ACCESS_CONTROL_REQUEST_HEADERS, "content-type")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            response
                .headers()
                .get(header::ACCESS_CONTROL_ALLOW_ORIGIN)
                .is_some(),
            allowed,
            "{origin}"
        );
        assert!(
            response
                .headers()
                .get(header::ACCESS_CONTROL_ALLOW_CREDENTIALS)
                .is_none()
        );
    }
}

#[tokio::test]
async fn missing_routes_and_methods_are_structured_errors() {
    let (status, value) = call(Method::GET, "/not-real", Value::Null).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(value["error"]["code"], "not_found");
    let (status, value) = call(Method::GET, "/api/v1/preview", Value::Null).await;
    assert_eq!(status, StatusCode::METHOD_NOT_ALLOWED);
    assert_eq!(value["error"]["code"], "method_not_allowed");
}

#[tokio::test]
async fn repeated_requests_are_deterministic_and_do_not_create_records() {
    let (_, first) = call(Method::POST, "/api/v1/preview", request()).await;
    let (_, second) = call(Method::POST, "/api/v1/preview", request()).await;
    assert_eq!(first, second);
    assert!(first.get("session_id").is_none());
    assert!(first.get("user_id").is_none());
    let (status, _) = call(Method::GET, "/api/v1/history", Value::Null).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn catalog_publishes_the_enforced_selection_limits() {
    let (_, catalog) = call(Method::GET, "/api/v1/catalog", Value::Null).await;
    assert_eq!(
        catalog["selection"],
        json!({"min_changes": senior_meal_preview::MIN_CHANGES, "max_changes": senior_meal_preview::MAX_CHANGES})
    );
    assert_eq!(
        catalog["selection"],
        json!({"min_changes":1,"max_changes":2})
    );
}

#[tokio::test]
async fn catalog_is_internally_consistent() {
    let (_, catalog) = call(Method::GET, "/api/v1/catalog", Value::Null).await;
    let dish_ids: Vec<&str> = catalog["dishes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|dish| dish["id"].as_str().unwrap())
        .collect();
    let change_ids: Vec<&str> = catalog["changes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|change| change["id"].as_str().unwrap())
        .collect();
    for (index, id) in dish_ids.iter().enumerate() {
        assert!(!dish_ids[..index].contains(id), "duplicate dish {id}");
    }
    for (index, id) in change_ids.iter().enumerate() {
        assert!(!change_ids[..index].contains(id), "duplicate change {id}");
    }
    for change in catalog["changes"].as_array().unwrap() {
        let compatible = change["dish_ids"].as_array().unwrap();
        assert!(!compatible.is_empty(), "{} has no dishes", change["id"]);
        for dish_id in compatible {
            assert!(
                dish_ids.contains(&dish_id.as_str().unwrap()),
                "{} references unknown dish {dish_id}",
                change["id"]
            );
        }
    }
    for dish_id in &dish_ids {
        assert!(
            catalog["changes"]
                .as_array()
                .unwrap()
                .iter()
                .any(|change| change["dish_ids"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|id| id == dish_id)),
            "{dish_id} has no compatible change"
        );
    }
}

#[tokio::test]
async fn duplicates_are_reported_before_unknown_or_incompatible_ids() {
    for body in [
        json!({"dish_id":"chicken_rice","change_ids":["magic","magic"]}),
        json!({"dish_id":"fish_soup","change_ids":["brown_rice","brown_rice"]}),
    ] {
        let (status, value) = call(Method::POST, "/api/v1/preview", body).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(value["error"]["code"], "duplicate_change");
    }
}

/// A request body that never delivers data, standing in for a stalled client.
struct StalledBody;

impl axum::body::HttpBody for StalledBody {
    type Data = axum::body::Bytes;
    type Error = std::convert::Infallible;

    fn poll_frame(
        self: std::pin::Pin<&mut Self>,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Result<http_body::Frame<Self::Data>, Self::Error>>> {
        std::task::Poll::Pending
    }
}

#[tokio::test]
async fn stalled_requests_time_out_with_a_structured_error() {
    let response = senior_meal_preview::app_with_timeout(std::time::Duration::from_millis(50))
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/api/v1/preview")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::new(StalledBody))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::REQUEST_TIMEOUT);
    assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(value["error"]["code"], "timeout");
}

#[test]
fn tailscale_worker_url_validation_blocks_ssrf_and_imds() {
    use senior_meal_preview::worker::{WorkerTransport, validate_worker_url};

    let ts_ip = validate_worker_url("http://100.101.102.103:8790").unwrap();
    assert_eq!(ts_ip.transport, WorkerTransport::Tailscale);
    assert_eq!(ts_ip.port, 8790);

    let ts_dns = validate_worker_url("http://gpu-box.tail1234.ts.net:8790/prefix/").unwrap();
    assert_eq!(ts_dns.transport, WorkerTransport::Tailscale);
    assert_eq!(ts_dns.path_prefix, "/prefix");

    let ts_v6 = validate_worker_url("http://[fd7a:115c:a1e0::1234]:8790").unwrap();
    assert_eq!(ts_v6.transport, WorkerTransport::Tailscale);

    let lo = validate_worker_url("http://127.0.0.1:8790").unwrap();
    assert_eq!(lo.transport, WorkerTransport::Loopback);

    // Block EC2 IMDS, RFC1918 LAN, non-Tailscale 100.x, public domains, and credentials.
    for forbidden in [
        "http://169.254.169.254/latest/meta-data",
        "http://10.0.0.12:8790",
        "http://192.168.1.10:8790",
        "http://172.16.0.5:8790",
        "http://100.63.255.255:8790",
        "http://100.128.0.1:8790",
        "http://example.com:8790",
        "http://evil.ts.net.attacker.com:8790",
        "http://user:pass@100.100.100.100:8790",
        "https://100.100.100.100:8790",
    ] {
        assert!(
            validate_worker_url(forbidden).is_err(),
            "should reject {forbidden}"
        );
    }
}

#[tokio::test]
async fn gpu_assisted_mode_fails_truthfully_when_worker_not_configured() {
    let mut body = request();
    body["render_mode"] = json!("gpu_assisted");
    let (status, value) = call(Method::POST, "/api/v1/preview", body).await;
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(value["error"]["code"], "gpu_unavailable");
}

#[tokio::test]
async fn gpu_assisted_mode_bridges_to_authenticated_worker_and_validates_artifact() {
    use senior_meal_preview::{RuntimeConfig, worker::GpuWorkerConfig};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();

    let server_task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut buf = Vec::with_capacity(1024);
        let mut chunk = [0u8; 512];
        loop {
            let n = socket.read(&mut chunk).await.unwrap();
            if n == 0 {
                break;
            }
            buf.extend_from_slice(&chunk[..n]);
            if buf.ends_with(b"}") {
                break;
            }
        }
        let req_text = String::from_utf8_lossy(&buf);
        assert!(req_text.contains("POST /v1/generate HTTP/1.1"));
        assert!(req_text.contains("Authorization: Bearer ts-secret-token"));
        assert!(req_text.contains("\"dish_id\":\"chicken_rice\""));

        let response_json = json!({
            "provider": "tailscale-gpu-worker",
            "model": "brushnet-sdxl+qwen2.5-vl-7b-4bit",
            "prompt_id": "t2_r1_hawker_t1b_broccoli",
            "seed": 42,
            "attempts": 2,
            "checker_passed": true,
            "image_data_url": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
            "generated_label": "AI-generated preview · Not a real meal or clinical verification"
        })
        .to_string();
        let http_resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            response_json.len(),
            response_json
        );
        socket.write_all(http_resp.as_bytes()).await.unwrap();
    });

    let worker_cfg = GpuWorkerConfig::new(
        &format!("http://127.0.0.1:{}", addr.port()),
        Some("ts-secret-token".into()),
        std::time::Duration::from_secs(5),
        2,
    )
    .unwrap();
    let app = senior_meal_preview::app_with_config(RuntimeConfig {
        gpu_worker: Some(worker_cfg),
        ..RuntimeConfig::default()
    });

    let mut body = request();
    body["render_mode"] = json!("gpu_assisted");
    let response = app
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/api/v1/preview")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let value: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(value["gpu_artifact"]["provider"], "tailscale-gpu-worker");
    assert_eq!(value["gpu_artifact"]["attempts"], 2);
    assert_eq!(value["gpu_artifact"]["checker_passed"], true);
    server_task.await.unwrap();
}

#[tokio::test]
async fn worker_refusals_are_reported_truthfully_not_as_outages() {
    use senior_meal_preview::{RuntimeConfig, worker::GpuWorkerConfig};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    for (worker_status, api_status, code) in [
        (
            "422 Unprocessable Entity",
            StatusCode::UNPROCESSABLE_ENTITY,
            "gpu_unsupported_request",
        ),
        (
            "503 Service Unavailable",
            StatusCode::SERVICE_UNAVAILABLE,
            "gpu_not_ready",
        ),
        (
            "500 Internal Server Error",
            StatusCode::BAD_GATEWAY,
            "gpu_unreachable",
        ),
    ] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let server_task = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut buf = Vec::new();
            let mut chunk = [0u8; 512];
            while !buf.ends_with(b"}") {
                let n = socket.read(&mut chunk).await.unwrap();
                if n == 0 {
                    break;
                }
                buf.extend_from_slice(&chunk[..n]);
            }
            let body = r#"{"error":"worker_refused","message":"internal detail"}"#;
            let response = format!(
                "HTTP/1.1 {worker_status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
                body.len()
            );
            socket.write_all(response.as_bytes()).await.unwrap();
        });
        let worker_cfg = GpuWorkerConfig::new(
            &format!("http://127.0.0.1:{port}"),
            None,
            std::time::Duration::from_secs(5),
            1,
        )
        .unwrap();
        let app = senior_meal_preview::app_with_config(RuntimeConfig {
            gpu_worker: Some(worker_cfg),
            ..RuntimeConfig::default()
        });
        let mut body = request();
        body["render_mode"] = json!("gpu_assisted");
        let response = app
            .oneshot(
                Request::builder()
                    .method(Method::POST)
                    .uri("/api/v1/preview")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), api_status);
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        let value: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(value["error"]["code"], code);
        assert!(value.get("gpu_artifact").is_none());
        // Worker-internal detail is never forwarded to clients.
        assert!(!value.to_string().contains("internal detail"));
        server_task.await.unwrap();
    }
}

#[tokio::test]
async fn ec2_api_token_and_configured_origins_are_enforced() {
    use senior_meal_preview::RuntimeConfig;

    let app = senior_meal_preview::app_with_config(RuntimeConfig {
        api_token: Some("ec2-prod-token".into()),
        allowed_origins: vec!["https://mealpreview.example.com".into()],
        ..RuntimeConfig::default()
    });

    // /healthz remains unauthenticated for EC2/ALB/Caddy probes.
    let health = app
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/healthz")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(health.status(), StatusCode::OK);

    // /api/v1/catalog rejects missing bearer token.
    let unauth = app
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/api/v1/catalog")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(unauth.status(), StatusCode::UNAUTHORIZED);

    // /api/v1/catalog succeeds with valid bearer token and allows configured HTTPS origin.
    let authed = app
        .oneshot(
            Request::builder()
                .method(Method::GET)
                .uri("/api/v1/catalog")
                .header(header::AUTHORIZATION, "Bearer ec2-prod-token")
                .header(header::ORIGIN, "https://mealpreview.example.com")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(authed.status(), StatusCode::OK);
    assert_eq!(
        authed.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN],
        "https://mealpreview.example.com"
    );
}

#[tokio::test]
async fn catalog_requires_a_current_real_gpu_health_response() {
    use senior_meal_preview::{RuntimeConfig, worker::GpuWorkerConfig};
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };

    for (status, payload, expected) in [
        (
            200,
            r#"{"status":"ok","worker_mode":"gpu","gpu_ready":true}"#,
            true,
        ),
        (
            200,
            r#"{"status":"ok","worker_mode":"gpu","gpu_ready":false}"#,
            false,
        ),
        // Legacy dry-run workers incorrectly report true; mode must also be checked.
        (
            200,
            r#"{"status":"ok","worker_mode":"dry-run","gpu_ready":true}"#,
            false,
        ),
        (
            200,
            r#"{"status":"ok","worker_mode":"dry-run","gpu_ready":false}"#,
            false,
        ),
        (
            200,
            r#"{"status":"error","worker_mode":"gpu","gpu_ready":true}"#,
            false,
        ),
        (200, r#"{"gpu_ready":true}"#, false),
        (
            200,
            r#"{"status":"ok","worker_mode":"gpu","gpu_ready":"true"}"#,
            false,
        ),
        (200, "not json", false),
        (
            503,
            r#"{"status":"ok","worker_mode":"gpu","gpu_ready":true}"#,
            false,
        ),
        (
            401,
            r#"{"status":"ok","worker_mode":"gpu","gpu_ready":true}"#,
            false,
        ),
    ] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut bytes = Vec::new();
            loop {
                let mut chunk = [0; 512];
                let n = socket.read(&mut chunk).await.unwrap();
                if n == 0 {
                    break;
                }
                bytes.extend_from_slice(&chunk[..n]);
                if bytes.windows(4).any(|w| w == b"\r\n\r\n") {
                    break;
                }
            }
            let req = String::from_utf8_lossy(&bytes);
            assert!(req.starts_with("GET /prefix/healthz HTTP/1.1"));
            assert!(req.contains("Authorization: Bearer test-only-token"));
            let response = format!(
                "HTTP/1.1 {status} Status\r\nContent-Length: {}\r\n\r\n{payload}",
                payload.len()
            );
            socket.write_all(response.as_bytes()).await.unwrap();
        });
        let cfg = GpuWorkerConfig::new(
            &format!("http://{addr}/prefix"),
            Some("test-only-token".into()),
            std::time::Duration::from_secs(2),
            1,
        )
        .unwrap();
        let response = senior_meal_preview::app_with_config(RuntimeConfig {
            gpu_worker: Some(cfg),
            ..RuntimeConfig::default()
        })
        .oneshot(
            Request::builder()
                .uri("/api/v1/catalog")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        let catalog: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            catalog["capabilities"]["gpu_preview"], expected,
            "{status}: {payload}"
        );
        assert_eq!(catalog["capabilities"]["symbolic_preview"], true);
        server.await.unwrap();
    }
}

#[tokio::test]
async fn readiness_timeout_and_unreachable_worker_fail_closed() {
    use senior_meal_preview::worker::{GpuWorkerConfig, gpu_preview_ready};
    use tokio::net::TcpListener;
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let cfg = GpuWorkerConfig::new(
        &format!("http://{addr}"),
        None,
        std::time::Duration::from_millis(20),
        1,
    )
    .unwrap();
    assert!(!gpu_preview_ready(&cfg).await);
    drop(listener);
    assert!(!gpu_preview_ready(&cfg).await);
}
