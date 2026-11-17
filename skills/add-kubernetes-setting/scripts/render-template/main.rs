//! Render Bottlerocket templates the way schnauzer does on a node (strict mode, the real helpers),
//! with settings read from a JSON file instead of the Bottlerocket API.
//!
//! Before rendering, settings.kubernetes is deserialized into KubernetesSettingsV1 and serialized
//! back, which applies the same validation and normalization (for example canonical enum spellings)
//! that the API applies on `apiclient set` or user data. Invalid settings exit with status 3.
//!
//! Usage: br-render-template SETTINGS_JSON OUT_DIR TEMPLATE...
//! Each TEMPLATE is written to OUT_DIR/<parent-dir>__<file-name>.

use bottlerocket_settings_models::KubernetesSettingsV1;
use schnauzer::v2::import::{JsonSettingsResolver, StaticHelperResolver};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

struct Importer {
    settings_resolver: JsonSettingsResolver,
    helper_resolver: StaticHelperResolver,
}

schnauzer::impl_template_importer!(Importer, JsonSettingsResolver, StaticHelperResolver);

fn normalize(mut settings: serde_json::Value) -> Result<serde_json::Value, String> {
    if let Some(kubernetes) = settings.pointer_mut("/settings/kubernetes") {
        let model: KubernetesSettingsV1 = serde_json::from_value(kubernetes.clone())
            .map_err(|e| format!("settings.kubernetes would be rejected by the API: {e}"))?;
        *kubernetes = serde_json::to_value(model).map_err(|e| e.to_string())?;
    }
    Ok(settings)
}

#[tokio::main]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: br-render-template SETTINGS_JSON OUT_DIR TEMPLATE...");
        return ExitCode::from(2);
    }
    let settings = match std::fs::read_to_string(&args[1])
        .map_err(|e| e.to_string())
        .and_then(|text| serde_json::from_str(&text).map_err(|e| e.to_string()))
        .and_then(normalize)
    {
        Ok(settings) => settings,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(3);
        }
    };
    let out_dir = PathBuf::from(&args[2]);
    if let Err(e) = std::fs::create_dir_all(&out_dir) {
        eprintln!("{}: {e}", out_dir.display());
        return ExitCode::from(2);
    }
    let importer = Importer {
        settings_resolver: JsonSettingsResolver::new(settings),
        helper_resolver: StaticHelperResolver,
    };

    let mut failed = false;
    for template in &args[3..] {
        let path = Path::new(template);
        let parent = path
            .parent()
            .and_then(Path::file_name)
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        match schnauzer::v2::render_template_file(&importer, path).await {
            Ok(rendered) => {
                let out = out_dir.join(format!("{parent}__{name}"));
                if let Err(e) = std::fs::write(&out, rendered) {
                    eprintln!("{}: {e}", out.display());
                    failed = true;
                }
            }
            Err(e) => {
                eprintln!("{template}: render failed: {e}");
                failed = true;
            }
        }
    }
    if failed {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
}
