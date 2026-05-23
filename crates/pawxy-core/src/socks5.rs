use crate::error::{PawxyError, Result};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SocksAddr {
    Ip(std::net::IpAddr),
    Domain(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SocksTarget {
    pub addr: SocksAddr,
    pub port: u16,
}

pub const METHOD_NO_AUTH: u8 = 0x00;
pub const METHOD_USERNAME_PASSWORD: u8 = 0x02;
pub const METHOD_NO_ACCEPTABLE: u8 = 0xff;

pub fn choose_auth_method(methods: &[u8], auth_required: bool) -> Option<u8> {
    let wanted = if auth_required {
        METHOD_USERNAME_PASSWORD
    } else {
        METHOD_NO_AUTH
    };
    methods.iter().copied().find(|method| *method == wanted)
}

pub fn username_password_matches(payload: &[u8], username: &str, password: &str) -> Result<bool> {
    if payload.len() < 3 || payload[0] != 0x01 {
        return Err(PawxyError::Parse(
            "invalid SOCKS5 username/password payload",
        ));
    }
    let username_len = payload[1] as usize;
    let password_len_index = 2 + username_len;
    if payload.len() <= password_len_index {
        return Err(PawxyError::Parse("truncated SOCKS5 username"));
    }
    let password_len = payload[password_len_index] as usize;
    let password_start = password_len_index + 1;
    let password_end = password_start + password_len;
    if payload.len() != password_end {
        return Err(PawxyError::Parse("truncated SOCKS5 password"));
    }
    let got_username = std::str::from_utf8(&payload[2..password_len_index])?;
    let got_password = std::str::from_utf8(&payload[password_start..password_end])?;
    Ok(got_username == username && got_password == password)
}

pub fn parse_connect_target(payload: &[u8]) -> Result<SocksTarget> {
    if payload.len() < 7 || payload[0] != 0x05 {
        return Err(PawxyError::Parse("invalid SOCKS5 request"));
    }
    if payload[1] != 0x01 {
        return Err(PawxyError::Protocol("SOCKS5 only supports CONNECT"));
    }
    if payload[2] != 0x00 {
        return Err(PawxyError::Parse("invalid SOCKS5 reserved byte"));
    }
    let atyp = payload[3];
    let (addr, port_offset) = match atyp {
        0x01 => {
            if payload.len() < 10 {
                return Err(PawxyError::Parse("truncated SOCKS5 IPv4 target"));
            }
            let ip = std::net::Ipv4Addr::new(payload[4], payload[5], payload[6], payload[7]);
            (SocksAddr::Ip(std::net::IpAddr::V4(ip)), 8)
        }
        0x04 => {
            if payload.len() < 22 {
                return Err(PawxyError::Parse("truncated SOCKS5 IPv6 target"));
            }
            let mut octets = [0_u8; 16];
            octets.copy_from_slice(&payload[4..20]);
            (
                SocksAddr::Ip(std::net::IpAddr::V6(std::net::Ipv6Addr::from(octets))),
                20,
            )
        }
        0x03 => {
            let domain_len = payload[4] as usize;
            let domain_start = 5;
            let domain_end = domain_start + domain_len;
            if payload.len() < domain_end + 2 {
                return Err(PawxyError::Parse("truncated SOCKS5 domain target"));
            }
            let domain = std::str::from_utf8(&payload[domain_start..domain_end])?;
            (SocksAddr::Domain(domain.to_string()), domain_end)
        }
        _ => return Err(PawxyError::Protocol("unsupported SOCKS5 address type")),
    };
    let port = u16::from_be_bytes([payload[port_offset], payload[port_offset + 1]]);
    Ok(SocksTarget { addr, port })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

    #[test]
    fn socks5_greeting_selects_no_auth() {
        assert_eq!(choose_auth_method(&[0x00, 0x02], false), Some(0x00));
        assert_eq!(choose_auth_method(&[0x02], false), None);
    }

    #[test]
    fn socks5_username_password_success_and_failure() {
        let ok = username_password_matches(
            &[
                0x01, 0x05, b'p', b'a', b'w', b'x', b'y', 0x04, b'p', b'a', b's', b's',
            ],
            "pawxy",
            "pass",
        )
        .expect("valid auth payload");
        assert!(ok);

        let bad = username_password_matches(
            &[
                0x01, 0x05, b'p', b'a', b'w', b'x', b'y', 0x04, b'n', b'o', b'p', b'e',
            ],
            "pawxy",
            "pass",
        )
        .expect("valid auth payload");
        assert!(!bad);
    }

    #[test]
    fn socks5_parses_ipv4_ipv6_and_domain_targets() {
        let ipv4 = parse_connect_target(&[0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x1f, 0x90])
            .expect("ipv4 target");
        assert_eq!(
            ipv4.addr,
            SocksAddr::Ip(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)))
        );
        assert_eq!(ipv4.port, 8080);

        let ipv6 = parse_connect_target(&[
            0x05, 0x01, 0x00, 0x04, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x00, 0x50,
        ])
        .expect("ipv6 target");
        assert_eq!(ipv6.addr, SocksAddr::Ip(IpAddr::V6(Ipv6Addr::LOCALHOST)));
        assert_eq!(ipv6.port, 80);

        let domain = parse_connect_target(&[
            0x05, 0x01, 0x00, 0x03, 11, b'e', b'x', b'a', b'm', b'p', b'l', b'e', b'.', b'c', b'o',
            b'm', 0x01, 0xbb,
        ])
        .expect("domain target");
        assert_eq!(domain.addr, SocksAddr::Domain("example.com".to_string()));
        assert_eq!(domain.port, 443);
    }
}
