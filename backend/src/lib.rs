//! Local-only, stateless illustrative meal-preview API. No image or model pipeline.

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, rejection::JsonRejection},
    http::{HeaderValue, Method, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde::{Deserialize, Serialize};
use tower_http::cors::{AllowOrigin, CorsLayer};

pub const MODE: &str = "illustrative_only";
pub const NOTICE: &str = "Prototype only. Illustrations are not model results or nutrition advice.";

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

#[derive(Serialize)]
pub struct Catalog {
    schema_version: u8,
    mode: &'static str,
    dishes: Vec<Dish>,
    changes: Vec<Change>,
    notice: &'static str,
}

pub fn catalog() -> Catalog {
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
                description: "An illustrative extra vegetable side",
                dish_ids: vec!["chicken_rice", "fish_soup", "tofu_rice"],
            },
            Change {
                id: "brown_rice",
                label: "Try brown rice",
                description: "An illustrative rice swap",
                dish_ids: vec!["chicken_rice", "tofu_rice"],
            },
            Change {
                id: "sauce_on_side",
                label: "Sauce on the side",
                description: "An illustrative serving change",
                dish_ids: vec!["chicken_rice", "tofu_rice"],
            },
        ],
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
        .into_iter()
        .find(|dish| dish.id == request.dish_id)
        .ok_or_else(|| ApiError::invalid("unknown_dish", "Choose a meal from the catalog."))?;
    if !(1..=2).contains(&request.change_ids.len()) {
        return Err(ApiError::invalid(
            "change_count",
            "Choose one or two meal changes.",
        ));
    }
    if request.change_ids.len() == 2 && request.change_ids[0] == request.change_ids[1] {
        return Err(ApiError::invalid(
            "duplicate_change",
            "Choose different meal changes.",
        ));
    }
    let mut targets = Vec::with_capacity(2);
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
    let summary = format!(
        "Illustrative request for {}: {}.",
        dish.name,
        names.join(" and ")
    );
    let mut notices = vec![
        NOTICE,
        "No photo is uploaded and no AI model is called. Your choices are not saved by this API.",
        "A picture cannot establish ingredients, portion quantities, allergens, nutritional value or health benefit.",
        "Preferences describe what you would like; this prototype does not validate or change a real recipe.",
    ];
    if request.preferences.texture == Texture::Soft {
        notices.push("A soft-texture preference does not establish chewing or swallowing safety. Follow your clinician's advice for any prescribed diet.");
    }
    Ok(Preview {
        schema_version: 1,
        mode: MODE,
        dish,
        edit_targets: targets,
        preferences: request.preferences,
        summary,
        notices,
    })
}

async fn preview(
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
    make_preview(request).map(Json)
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

pub fn app() -> Router {
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(|origin: &HeaderValue, _| {
            local_web_origin(origin)
        }))
        .allow_methods([Method::GET, Method::POST])
        .allow_headers([header::CONTENT_TYPE]);
    Router::new()
        .route(
            "/healthz",
            get(|| async {
                Json(Health {
                    status: "ok",
                    mode: MODE,
                })
            }),
        )
        .route("/api/v1/catalog", get(|| async { Json(catalog()) }))
        .route("/api/v1/preview", post(preview))
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
        .layer(DefaultBodyLimit::max(16 * 1024))
        .layer(cors)
        .layer(axum::middleware::map_response(
            |mut response: Response| async move {
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
struct Health {
    status: &'static str,
    mode: &'static str,
}
