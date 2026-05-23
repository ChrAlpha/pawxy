use crate::config::AuthConfig;
use crate::error::{PawxyError, Result};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HttpRequestHead {
    pub method: String,
    pub target: String,
    pub version: u8,
    pub headers: Vec<(String, String)>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HttpTarget {
    pub host: String,
    pub port: u16,
}

pub fn parse_request_head(header: &[u8]) -> Result<HttpRequestHead> {
    let mut headers = [httparse::EMPTY_HEADER; 64];
    let mut request = httparse::Request::new(&mut headers);
    match request
        .parse(header)
        .map_err(|_| PawxyError::Parse("invalid HTTP request"))?
    {
        httparse::Status::Complete(_) => {}
        httparse::Status::Partial => return Err(PawxyError::Parse("partial HTTP request")),
    }

    let method = request
        .method
        .ok_or(PawxyError::Parse("missing HTTP method"))?
        .to_string();
    let target = request
        .path
        .ok_or(PawxyError::Parse("missing HTTP target"))?
        .to_string();
    let version = request
        .version
        .ok_or(PawxyError::Parse("missing HTTP version"))?;
    let mut owned_headers = Vec::new();
    for header in request.headers {
        let value = std::str::from_utf8(header.value)?.trim().to_string();
        owned_headers.push((header.name.to_string(), value));
    }

    Ok(HttpRequestHead {
        method,
        target,
        version,
        headers: owned_headers,
    })
}

pub fn parse_connect_target(target: &str) -> Result<HttpTarget> {
    if let Some(rest) = target.strip_prefix('[') {
        let Some(end) = rest.find(']') else {
            return Err(PawxyError::Parse("invalid IPv6 CONNECT target"));
        };
        let host = &rest[..end];
        let port_text = rest[end + 1..]
            .strip_prefix(':')
            .ok_or(PawxyError::Parse("CONNECT target missing port"))?;
        let port = parse_port(port_text)?;
        return Ok(HttpTarget {
            host: host.to_string(),
            port,
        });
    }

    let (host, port_text) = target
        .rsplit_once(':')
        .ok_or(PawxyError::Parse("CONNECT target missing port"))?;
    if host.is_empty() {
        return Err(PawxyError::Parse("CONNECT target missing host"));
    }
    Ok(HttpTarget {
        host: host.to_string(),
        port: parse_port(port_text)?,
    })
}

pub fn proxy_auth_allowed(headers: &[(String, String)], auth: Option<&AuthConfig>) -> bool {
    let Some(auth) = auth else {
        return true;
    };
    headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("Proxy-Authorization"))
        .is_some_and(|(_, value)| crate::auth::basic_auth_matches(value, auth))
}

pub fn rewrite_absolute_form_request(head: &HttpRequestHead) -> Result<(HttpTarget, Vec<u8>)> {
    let (target, origin_form) = parse_absolute_http_target(&head.target)?;
    let mut bytes = Vec::new();
    bytes.extend_from_slice(
        format!(
            "{} {} HTTP/1.{}\r\n",
            head.method, origin_form, head.version
        )
        .as_bytes(),
    );
    for (name, value) in &head.headers {
        if name.eq_ignore_ascii_case("Proxy-Authorization")
            || name.eq_ignore_ascii_case("Proxy-Connection")
        {
            continue;
        }
        bytes.extend_from_slice(format!("{name}: {value}\r\n").as_bytes());
    }
    bytes.extend_from_slice(b"\r\n");
    Ok((target, bytes))
}

pub fn is_supported_http_method(method: &str) -> bool {
    matches!(
        method,
        "CONNECT" | "GET" | "POST" | "PUT" | "DELETE" | "PATCH" | "HEAD" | "OPTIONS"
    )
}

pub fn response_400() -> &'static [u8] {
    b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
}

pub fn response_407() -> &'static [u8] {
    b"HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"Pawxy\"\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
}

pub fn response_502() -> &'static [u8] {
    b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
}

fn parse_absolute_http_target(target: &str) -> Result<(HttpTarget, String)> {
    let rest = target.strip_prefix("http://").ok_or(PawxyError::Parse(
        "only http absolute-form URLs are supported",
    ))?;
    let split_at = rest.find(['/', '?']).unwrap_or(rest.len());
    let authority = &rest[..split_at];
    if authority.is_empty() {
        return Err(PawxyError::Parse("absolute-form URL missing host"));
    }
    let suffix = &rest[split_at..];
    let origin_form = if suffix.is_empty() {
        "/".to_string()
    } else if suffix.starts_with('?') {
        format!("/{suffix}")
    } else {
        suffix.to_string()
    };

    let target = if let Some(after_bracket) = authority.strip_prefix('[') {
        let Some(end) = after_bracket.find(']') else {
            return Err(PawxyError::Parse("invalid IPv6 URL host"));
        };
        let host = &after_bracket[..end];
        let port = if after_bracket.len() == end + 1 {
            80
        } else {
            parse_port(
                after_bracket[end + 1..]
                    .strip_prefix(':')
                    .ok_or(PawxyError::Parse("invalid IPv6 URL port"))?,
            )?
        };
        HttpTarget {
            host: host.to_string(),
            port,
        }
    } else if let Some((host, port_text)) = authority.rsplit_once(':') {
        HttpTarget {
            host: host.to_string(),
            port: parse_port(port_text)?,
        }
    } else {
        HttpTarget {
            host: authority.to_string(),
            port: 80,
        }
    };

    Ok((target, origin_form))
}

fn parse_port(port_text: &str) -> Result<u16> {
    port_text
        .parse::<u16>()
        .map_err(|_| PawxyError::Parse("invalid port"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::AuthConfig;

    #[test]
    fn parses_http_connect_target() {
        let target = parse_connect_target("example.com:443").expect("target");
        assert_eq!(target.host, "example.com");
        assert_eq!(target.port, 443);
    }

    #[test]
    fn validates_http_basic_auth() {
        let auth = AuthConfig {
            username: "pawxy".to_string(),
            password: "secret".to_string(),
        };
        let allowed = proxy_auth_allowed(
            &[(
                "Proxy-Authorization".to_string(),
                "Basic cGF3eHk6c2VjcmV0".to_string(),
            )],
            Some(&auth),
        );
        assert!(allowed);

        let denied = proxy_auth_allowed(
            &[(
                "Proxy-Authorization".to_string(),
                "Basic cGF3eHk6d3Jvbmc=".to_string(),
            )],
            Some(&auth),
        );
        assert!(!denied);
    }

    #[test]
    fn rewrites_absolute_form_http_request() {
        let head = parse_request_head(
            b"GET http://example.com/a?b=1 HTTP/1.1\r\nHost: example.com\r\nProxy-Connection: keep-alive\r\nProxy-Authorization: Basic abc\r\nUser-Agent: test\r\n\r\n",
        )
        .expect("parse head");

        let (target, rewritten) = rewrite_absolute_form_request(&head).expect("rewrite");

        assert_eq!(target.host, "example.com");
        assert_eq!(target.port, 80);
        let text = String::from_utf8(rewritten).expect("utf8");
        assert!(text.starts_with("GET /a?b=1 HTTP/1.1\r\n"));
        assert!(text.contains("Host: example.com\r\n"));
        assert!(text.contains("User-Agent: test\r\n"));
        assert!(!text.contains("Proxy-Connection"));
        assert!(!text.contains("Proxy-Authorization"));
    }
}
