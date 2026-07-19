import sys

p = 'src/tui.rs'
s = open(p, encoding='utf-8').read()


def sub(old, new, n=1):
    global s
    if old not in s:
        sys.exit("MISSING: " + old[:80])
    s = s.replace(old, new, n)


# ------------------------------------------------------- prompt takes its caveat
sub("""/// The question a broadcast asks before it runs.
fn broadcast_prompt(agents: &[AgentEntry], targets: &[String], what: &str) -> String {
    let names: Vec<&str> = agents
        .iter()
        .filter(|agent| targets.contains(&agent.id))
        .map(|agent| agent.name.as_str())
        .collect();

    format!(
        "Write {what} into all {} of them — {}? Each config is changed separately, and undo is \\
         per agent.",
        names.len(),
        names.join(", ")
    )
}""",
    """/// The question a broadcast asks before it runs.
///
/// It names every agent rather than counting them. This is the widest edit the
/// program makes and it cannot be taken back in one step, so the blast radius
/// has to be readable in the question itself.
fn broadcast_prompt(agents: &[AgentEntry], targets: &[String], lead: &str, note: &str) -> String {
    let names: Vec<&str> = agents
        .iter()
        .filter(|agent| targets.contains(&agent.id))
        .map(|agent| agent.name.as_str())
        .collect();

    format!("{lead} on all {} of them — {}? {note}", names.len(), names.join(", "))
}""")

# ------------------------------------------------------- pickers carry the scope
sub("""struct PresetPicker {
    presets: Vec<Preset>,
    cursor: Cursor,
}""",
    """struct PresetPicker {
    presets: Vec<Preset>,
    cursor: Cursor,
    scope: Scope,
}""")

sub("""struct McpPresetPicker {
    presets: Vec<preset::McpPreset>,
    cursor: Cursor,
}""",
    """struct McpPresetPicker {
    presets: Vec<preset::McpPreset>,
    cursor: Cursor,
    scope: Scope,
}

impl McpPresetPicker {
    fn selected(&self) -> Option<&preset::McpPreset> {
        self.presets.get(self.cursor.index())
    }
}""")

sub("""struct RegistryPicker {
    /// What was last asked of the registry, and what is now filtering the answer.
    query: String,
    entries: Vec<registry::Entry>,
    matches: Vec<usize>,
    cursor: Cursor,
}""",
    """struct RegistryPicker {
    /// What was last asked of the registry, and what is now filtering the answer.
    query: String,
    entries: Vec<registry::Entry>,
    matches: Vec<usize>,
    cursor: Cursor,
    scope: Scope,
}""")

sub("""        let mut picker = Self { query, entries, matches: Vec::new(), cursor: Cursor::default() };
        picker.rebuild();
        picker""",
    """        let mut picker = Self {
            query,
            entries,
            matches: Vec::new(),
            cursor: Cursor::default(),
            scope: Scope::default(),
        };
        picker.rebuild();
        picker""")

sub("""                self.overlay = Some(Overlay::McpPresets(McpPresetPicker {
                    presets,
                    cursor: Cursor::default(),
                }))""",
    """                self.overlay = Some(Overlay::McpPresets(McpPresetPicker {
                    presets,
                    cursor: Cursor::default(),
                    scope: Scope::default(),
                }))""")

sub("""                Ok(presets) => {
                    self.overlay =
                        Some(Overlay::Presets(PresetPicker { presets, cursor: Cursor::default() }))
                }""",
    """                Ok(presets) => {
                    self.overlay = Some(Overlay::Presets(PresetPicker {
                        presets,
                        cursor: Cursor::default(),
                        scope: Scope::default(),
                    }))
                }""")

# ------------------------------------------------------- shared build + ask
sub("""    fn apply_mcp_preset(&mut self, entry: &preset::McpPreset) {
        let server = match entry.server(None) {
            Ok(server) => server,
            Err(err) => {
                self.say(Tone::Bad, format!("MCP preset {}: {err:#}", entry.id));
                return;
            }
        };

        let missing = entry.missing_env().iter().map(|var| format!("${var}")).collect();
        self.install_server("mcp preset", server, missing);
    }""",
    """    fn apply_mcp_preset(&mut self, entry: &preset::McpPreset) {
        if let Some((server, missing)) = self.mcp_preset_server(entry) {
            self.install_server("mcp preset", server, missing);
        }
    }

    /// The server a preset describes and the variables it still wants, or
    /// nothing once the reason has been reported.
    fn mcp_preset_server(
        &mut self,
        entry: &preset::McpPreset,
    ) -> Option<(mcp::Server, Vec<String>)> {
        match entry.server(None) {
            Ok(server) => {
                Some((server, entry.missing_env().iter().map(|var| format!("${var}")).collect()))
            }
            Err(err) => {
                self.say(Tone::Bad, format!("MCP preset {}: {err:#}", entry.id));
                None
            }
        }
    }

    /// Ask before writing the same thing into every agent that can take it.
    fn ask_broadcast(&mut self, reach: Reach, lead: &str, note: &str, pending: Pending) {
        let targets = reachable(&self.agents, reach);
        if targets.is_empty() {
            self.say(Tone::Bad, "no installed agent can take that");
            return;
        }

        let agent_id = self.agent().map(|agent| agent.id.clone()).unwrap_or_default();
        self.overlay = Some(Overlay::Confirm(Confirm {
            prompt: broadcast_prompt(&self.agents, &targets, lead, note),
            agent_id,
            subject_id: String::new(),
            pending,
            every: targets,
        }));
    }

    /// Restore every agent's config from its own backup.
    fn ask_undo_all(&mut self) {
        self.ask_broadcast(
            Reach::Providers,
            "Restore the backup",
            "Each agent is restored from its own backup, and an agent this program never wrote \\
             to is left alone.",
            Pending::Undo,
        );
    }""")

sub("""    /// Add a registry entry to the selected agent.
    fn install_registry(&mut self, entry: &registry::Entry) {
        match entry.to_server(None) {
            Ok(server) => self.install_server("mcp install", server, missing_env_of(entry)),
            Err(err) => self.say(Tone::Bad, format!("{err:#}")),
        }
    }""",
    """    /// Add a registry entry to the selected agent.
    fn install_registry(&mut self, entry: &registry::Entry) {
        if let Some((server, missing)) = self.registry_server(entry) {
            self.install_server("mcp install", server, missing);
        }
    }

    /// The server a registry entry would launch, or nothing once the reason it
    /// would not has been reported.
    fn registry_server(&mut self, entry: &registry::Entry) -> Option<(mcp::Server, Vec<String>)> {
        match entry.to_server(None) {
            Ok(server) => Some((server, missing_env_of(entry))),
            Err(err) => {
                self.say(Tone::Bad, format!("{err:#}"));
                None
            }
        }
    }""")

open(p, 'w', encoding='utf-8').write(s)
print("ok")
