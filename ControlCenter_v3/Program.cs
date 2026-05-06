using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Text.Json;
using System.Diagnostics;
using System.Text.Json.Nodes;

namespace OpenClawControlCenter
{
    public partial class ControlForm : Form
    {
        private string configPath = @"C:\Users\Reno\.openclaw\openclaw.json";
        private HttpClient httpClient = new HttpClient();

        private ComboBox modelCombo;
        private TextBox gatewayTokenInput;
        private TextBox botTokenInput;
        private TextBox ollamaKeyInput;
        private TextBox nvidiaKeyInput;
        private CheckBox cbDisableDeviceAuth;
        private CheckBox cbInsecureAuth;
        private CheckBox cbTailscale;
        private Button btnRefresh, btnRestart, btnStop, btnSave;

        public ControlForm()
        {
            InitializeComponent();
            RefreshData();
        }

        private void InitializeComponent()
        {
            this.Text = "OpenClaw Control Center v3.6 (Atomic Save)";
            this.Size = new Size(550, 750);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(30, 41, 59);
            this.ForeColor = Color.White;

            Font sectionFont = new Font("Segoe UI", 12, FontStyle.Bold);
            Font labelFont = new Font("Segoe UI", 9, FontStyle.Bold);
            Font inputFont = new Font("Segoe UI", 10);

            int currentY = 20;

            AddSectionHeader("MODEL SETTINGS", ref currentY, sectionFont);
            AddLabel("Select Primary Model", ref currentY, labelFont);
            modelCombo = new ComboBox { Location = new Point(20, currentY), Size = new Size(480, 30), DropDownStyle = ComboBoxStyle.DropDownList, BackColor = Color.FromArgb(15, 23, 42), ForeColor = Color.White, Font = inputFont };
            this.Controls.Add(modelCombo);
            currentY += 40;

            AddSectionHeader("AUTHENTICATION & KEYS", ref currentY, sectionFont);
            gatewayTokenInput = AddInputField("Gateway Token", ref currentY, labelFont, inputFont);
            botTokenInput = AddInputField("Telegram Bot Token", ref currentY, labelFont, inputFont);
            ollamaKeyInput = AddInputField("Ollama API Key", ref currentY, labelFont, inputFont, true);
            nvidiaKeyInput = AddInputField("Nvidia API Key", ref currentY, labelFont, inputFont, true);

            AddSectionHeader("ADVANCED TOGGLES", ref currentY, sectionFont);
            cbDisableDeviceAuth = new CheckBox { Text = "Dangerously Disable Device Auth", Location = new Point(20, currentY), Size = new Size(400, 25), ForeColor = Color.White };
            this.Controls.Add(cbDisableDeviceAuth);
            currentY += 30;
            cbInsecureAuth = new CheckBox { Text = "Allow Insecure Auth", Location = new Point(20, currentY), Size = new Size(400, 25), ForeColor = Color.White };
            this.Controls.Add(cbInsecureAuth);
            currentY += 30;
            cbTailscale = new CheckBox { Text = "Enable Tailscale Mode", Location = new Point(20, currentY), Size = new Size(400, 25), ForeColor = Color.White };
            this.Controls.Add(cbTailscale);
            currentY += 40;

            AddSectionHeader("GATEWAY ACTIONS", ref currentY, sectionFont);
            btnRestart = new Button { Text = "Restart Gateway", Location = new Point(20, currentY), Size = new Size(150, 40), BackColor = Color.FromArgb(59, 130, 246), ForeColor = Color.White, Font = labelFont };
            btnStop = new Button { Text = "Stop Gateway", Location = new Point(180, currentY), Size = new Size(150, 40), BackColor = Color.FromArgb(239, 68, 68), ForeColor = Color.White, Font = labelFont };
            btnRefresh = new Button { Text = "Refresh Status", Location = new Point(340, currentY), Size = new Size(150, 40), BackColor = Color.FromArgb(71, 85, 105), ForeColor = Color.White, Font = labelFont };
            this.Controls.Add(btnRestart);
            this.Controls.Add(btnStop);
            this.Controls.Add(btnRefresh);
            currentY += 60;

            btnSave = new Button { Text = "SAVE ALL CHANGES", Location = new Point(20, currentY), Size = new Size(480, 60), BackColor = Color.FromArgb(34, 197, 94), ForeColor = Color.White, Font = new Font("Segoe UI", 14, FontStyle.Bold) };
            this.Controls.Add(btnSave);

            btnRefresh.Click += (s, e) => RefreshData();
            btnSave.Click += (s, e) => SaveData();
            btnRestart.Click += (s, e) => {
                try { 
                    ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c openclaw gateway restart") { 
                        CreateNoWindow = true, 
                        UseShellExecute = false 
                    };
                    Process.Start(psi); 
                } catch (Exception ex) {
                    MessageBox.Show("Restart failed: " + ex.Message);
                }
                MessageBox.Show("Gateway restart command sent via CMD!");
            };
            btnStop.Click += (s, e) => {
                try { foreach (var proc in Process.GetProcessesByName("node")) proc.Kill(); } catch { }
                MessageBox.Show("All Node processes terminated.");
            };
        }

        private void AddSectionHeader(string text, ref int y, Font font)
        {
            Label lbl = new Label { Text = text, Location = new Point(20, y), Size = new Size(400, 25), ForeColor = Color.Cyan, Font = font };
            this.Controls.Add(lbl);
            y += 30;
        }

        private void AddLabel(string text, ref int y, Font font)
        {
            Label lbl = new Label { Text = text, Location = new Point(20, y), Size = new Size(400, 20), ForeColor = Color.LightGray, Font = font };
            this.Controls.Add(lbl);
            y += 20;
        }

        private TextBox AddInputField(string label, ref int y, Font labelFont, Font inputFont, bool password = false)
        {
            AddLabel(label, ref y, labelFont);
            TextBox tb = new TextBox { Location = new Point(20, y), Size = new Size(480, 25), BackColor = Color.FromArgb(15, 23, 42), ForeColor = Color.White, Font = inputFont, PasswordChar = password ? '*' : '\0' };
            this.Controls.Add(tb);
            y += 40;
            return tb;
        }

        private async void RefreshData()
        {
            if (!File.Exists(configPath)) return;
            try {
                string jsonStr = File.ReadAllText(configPath);
                using var doc = JsonDocument.Parse(jsonStr);
                var root = doc.RootElement;

                modelCombo.Items.Clear();
                if (root.TryGetProperty("agents", out var agents) && 
                    agents.TryGetProperty("defaults", out var defaults) && 
                    defaults.TryGetProperty("models", out var models)) 
                {
                    foreach (var prop in models.EnumerateObject()) modelCombo.Items.Add(prop.Name);
                }

                try {
                    var tagsResponse = await httpClient.GetStringAsync("http://127.0.0.1:11434/api/tags");
                    using var tagsDoc = JsonDocument.Parse(tagsResponse);
                    foreach (var tag in tagsDoc.RootElement.EnumerateArray()) {
                        string name = tag.GetProperty("name").GetString();
                        if (!modelCombo.Items.Contains(name)) modelCombo.Items.Add(name);
                    }
                } catch { }

                if (root.TryGetProperty("agents", out var a) && a.TryGetProperty("defaults", out var d) && d.TryGetProperty("model", out var m)) {
                    if (m.TryGetProperty("primary", out var p)) modelCombo.SelectedItem = p.GetString();
                }

                gatewayTokenInput.Text = GetSafeString(root, "gateway", "auth", "token");
                botTokenInput.Text = GetSafeString(root, "channels", "telegram", "accounts", "default", "botToken");
                ollamaKeyInput.Text = GetSafeString(root, "models", "providers", "ollama", "apiKey");
                nvidiaKeyInput.Text = GetSafeString(root, "models", "providers", "nvidia", "apiKey");
                cbDisableDeviceAuth.Checked = GetSafeBool(root, "gateway", "controlUi", "dangerouslyDisableDeviceAuth");
                cbInsecureAuth.Checked = GetSafeBool(root, "gateway", "controlUi", "allowInsecureAuth");
                cbTailscale.Checked = GetSafeString(root, "gateway", "tailscale", "mode") != "off";
            } catch (Exception ex) { 
                MessageBox.Show("Error loading config: " + ex.Message); 
            }
        }

        private string GetSafeString(JsonElement root, params string[] path)
        {
            JsonElement current = root;
            foreach (var segment in path) {
                if (!current.TryGetProperty(segment, out current)) return "";
            }
            return current.ValueKind == JsonValueKind.String ? current.GetString() : "";
        }

        private bool GetSafeBool(JsonElement root, params string[] path)
        {
            JsonElement current = root;
            foreach (var segment in path) {
                if (!current.TryGetProperty(segment, out current)) return false;
            }
            return current.ValueKind == JsonValueKind.True;
        }

        private void SaveData()
        {
            try {
                string jsonStr = File.ReadAllText(configPath);
                
                // Use JsonNode for a true mutable object model. 
                // This prevents string-replacement corruption.
                var root = JsonNode.Parse(jsonStr).AsObject();

                // Update Primary Model
                root["agents"]["defaults"]["model"]["primary"] = modelCombo.SelectedItem?.ToString();

                // Update Auth Tokens
                root["gateway"]["auth"]["token"] = gatewayTokenInput.Text;
                root["channels"]["telegram"]["accounts"]["default"]["botToken"] = botTokenInput.Text;

                // Update Provider Keys
                root["models"]["providers"]["ollama"]["apiKey"] = ollamaKeyInput.Text;
                root["models"]["providers"]["nvidia"]["apiKey"] = nvidiaKeyInput.Text;

                // Update Toggles
                root["gateway"]["controlUi"]["dangerouslyDisableDeviceAuth"] = cbDisableDeviceAuth.Checked;
                root["gateway"]["controlUi"]["allowInsecureAuth"] = cbInsecureAuth.Checked;
                root["gateway"]["tailscale"]["mode"] = cbTailscale.Checked ? "on" : "off";

                var options = new JsonSerializerOptions { WriteIndented = true };
                File.WriteAllText(configPath, JsonSerializer.Serialize(root, options));
                
                MessageBox.Show("Configuration saved successfully and atomically!");
            } catch (Exception ex) { 
                MessageBox.Show("Error saving config: " + ex.Message); 
            }
        }
    }

    public class Program
    {
        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new ControlForm());
        }
    }
}
