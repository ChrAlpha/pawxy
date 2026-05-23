#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Protocol {
    Http,
    Socks5,
}

pub fn classify_prefix(prefix: &[u8]) -> Option<Protocol> {
    if prefix.first() == Some(&0x05) {
        return Some(Protocol::Socks5);
    }

    const METHODS: &[&[u8]] = &[
        b"CONNECT", b"GET", b"POST", b"PUT", b"DELETE", b"PATCH", b"HEAD", b"OPTIONS",
    ];
    METHODS
        .iter()
        .any(|method| prefix.starts_with(method))
        .then_some(Protocol::Http)
}
