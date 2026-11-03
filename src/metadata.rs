//! Release metadata, generated at build time by `BurritoNg.Steps.Build.PackAndBuild`
//! and written next to every install as `_metadata.json`.

use serde_json::Value;

#[derive(Debug, Clone)]
pub struct Metadata {
    pub app_name: String,
    pub app_version: String,
    pub erts_version: String,
}

impl Metadata {
    pub fn parse(json: &str) -> Result<Metadata, String> {
        let value: Value = serde_json::from_str(json).map_err(|e| e.to_string())?;

        let field = |name: &str| -> Result<String, String> {
            value
                .get(name)
                .and_then(Value::as_str)
                .map(str::to_owned)
                .ok_or_else(|| format!("missing string field `{name}`"))
        };

        Ok(Metadata {
            app_name: field("app_name")?,
            app_version: field("app_version")?,
            erts_version: field("erts_version")?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_metadata() {
        let meta = Metadata::parse(
            r#"{"app_name":"my_app","app_version":"1.2.3","erts_version":"15.2","options":"[]","build_arguments":["--release"]}"#,
        )
        .unwrap();
        assert_eq!(meta.app_name, "my_app");
        assert_eq!(meta.app_version, "1.2.3");
        assert_eq!(meta.erts_version, "15.2");
    }

    #[test]
    fn rejects_missing_fields() {
        assert!(Metadata::parse(r#"{"app_name":"my_app"}"#).is_err());
        assert!(Metadata::parse("not json").is_err());
    }
}
