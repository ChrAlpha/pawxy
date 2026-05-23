use crate::config::AuthConfig;

pub fn basic_auth_matches(header_value: &str, auth: &AuthConfig) -> bool {
    use base64::Engine;

    let mut parts = header_value.split_whitespace();
    let Some(scheme) = parts.next() else {
        return false;
    };
    let Some(encoded) = parts.next() else {
        return false;
    };
    if parts.next().is_some() || !scheme.eq_ignore_ascii_case("Basic") {
        return false;
    }

    let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(encoded) else {
        return false;
    };
    let expected = format!("{}:{}", auth.username, auth.password);
    decoded == expected.as_bytes()
}
