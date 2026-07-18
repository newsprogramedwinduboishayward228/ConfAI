//! Identity: the marks, the palette and the links, in one place.
//!
//! Everything user-visible pulls its colours and wording from here, so the CLI,
//! the TUI and the docs cannot drift apart.

use ratatui::style::Color;

pub const NAME: &str = "ConfAI";
pub const TAGLINE: &str = "one editor for every AI agent's config";
pub const VENDOR: &str = "redstone.md";
pub const WEBSITE: &str = "https://redstone.md";
pub const REPOSITORY: &str = "https://github.com/redstone-md/ConfAI";
/// The repository without its scheme, for places that are tight on width.
pub const REPOSITORY_SHORT: &str = "github.com/redstone-md/ConfAI";
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// The diamond is the mark; it stands in for the full logo wherever one line is
/// all there is room for.
pub const MARK: &str = "◆";

/// Full wordmark, for the about screen and `--version`.
pub const LOGO: &str = r"
 ██████╗ ██████╗ ███╗   ██╗███████╗ █████╗ ██╗
██╔════╝██╔═══██╗████╗  ██║██╔════╝██╔══██╗██║
██║     ██║   ██║██╔██╗ ██║█████╗  ███████║██║
██║     ██║   ██║██║╚██╗██║██╔══╝  ██╔══██║██║
╚██████╗╚██████╔╝██║ ╚████║██║     ██║  ██║██║
 ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝     ╚═╝  ╚═╝╚═╝";

/// Rows of [`LOGO`], without the leading blank line the raw literal carries.
pub fn logo_lines() -> impl Iterator<Item = &'static str> {
    LOGO.trim_matches('\n').lines()
}

/// Widest row of [`LOGO`], for centring it without measuring at every call site.
pub fn logo_width() -> usize {
    logo_lines().map(|line| line.chars().count()).max().unwrap_or(0)
}

/// One line naming the tool, its version and who makes it.
pub fn signature() -> String {
    format!("{NAME} {VERSION} · {VENDOR}")
}

/// The palette. Named by role rather than by hue, so a colour can be retuned in
/// one place without every use site becoming a lie.
pub mod palette {
    use super::Color;

    /// Redstone crimson: selection, focus, the mark itself.
    pub const ACCENT: Color = Color::Rgb(214, 69, 61);
    /// Accent at rest, for unfocused borders and rules.
    pub const ACCENT_MUTED: Color = Color::Rgb(122, 48, 44);
    /// Body text.
    pub const TEXT: Color = Color::Rgb(226, 223, 219);
    /// Labels, hints, anything secondary.
    pub const MUTED: Color = Color::Rgb(133, 128, 122);
    /// Barely there: separators, placeholder text.
    pub const FAINT: Color = Color::Rgb(88, 84, 80);
    /// Reachable, healthy, done.
    pub const GOOD: Color = Color::Rgb(126, 191, 111);
    /// Works but wants attention.
    pub const WARN: Color = Color::Rgb(226, 178, 88);
    /// Unreachable, rejected, failed.
    pub const BAD: Color = Color::Rgb(226, 94, 86);
    /// Background of a selected row.
    pub const SELECTION_BG: Color = Color::Rgb(58, 30, 28);
    /// Background of an overlay, so it reads as floating above the panes.
    pub const OVERLAY_BG: Color = Color::Rgb(24, 22, 21);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_wordmark_is_a_rectangle() {
        let widths: Vec<usize> = logo_lines().map(|line| line.chars().count()).collect();
        assert_eq!(widths.len(), 6);
        assert!(widths.windows(2).all(|pair| pair[0] == pair[1]), "ragged logo rows: {widths:?}");
        assert_eq!(logo_width(), widths[0]);
    }

    #[test]
    fn the_wordmark_uses_one_family_of_box_characters() {
        // Mixing single-line and double-line box drawing renders at two
        // different weights, which is what made the old compact mark look
        // broken. Block and double-line only.
        let stray: Vec<char> =
            LOGO.chars().filter(|c| matches!(c, '\u{2500}'..='\u{253F}')).collect();
        assert!(stray.is_empty(), "single-line box characters in the wordmark: {stray:?}");
    }

    #[test]
    fn links_are_absolute_so_they_are_clickable_when_pasted() {
        for link in [WEBSITE, REPOSITORY] {
            assert!(link.starts_with("https://"), "{link} is not an absolute URL");
        }
    }

    #[test]
    fn the_short_repository_is_the_same_link_without_its_scheme() {
        assert_eq!(REPOSITORY, format!("https://{REPOSITORY_SHORT}"));
    }

    #[test]
    fn the_signature_carries_the_name_version_and_vendor() {
        let signature = signature();
        assert!(signature.contains(NAME));
        assert!(signature.contains(VERSION));
        assert!(signature.contains(VENDOR));
    }
}
