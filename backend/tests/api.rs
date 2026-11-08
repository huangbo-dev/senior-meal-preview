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
            .contains("not model results")
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
