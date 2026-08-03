package org.safedesk.app;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
import android.widget.Button;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.appcompat.app.AppCompatActivity;

import com.journeyapps.barcodescanner.ScanContract;
import com.journeyapps.barcodescanner.ScanOptions;

import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Accueil : soit deja configure -> bureau, soit scan du code SafeDesk. */
public class MainActivity extends AppCompatActivity {

    private final ActivityResultLauncher<ScanOptions> scanner =
        registerForActivityResult(new ScanContract(), result -> {
            if (result.getContents() != null) handleCode(result.getContents());
        });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // QR unique : l app a ete ouverte par le lien https (App Link) -> config dans le fragment
        Uri link = getIntent().getData();
        if (link != null && applyCode(link.toString())) return;
        if (Config.isConfigured(this)) { openDesktop(); return; }
        // Application personnalisee : la config peut etre cuite dans l APK a la forge
        if (applyBakedConfig()) return;
        setContentView(R.layout.activity_main);
        Button scan = findViewById(R.id.btn_scan);
        scan.setOnClickListener(v -> {
            ScanOptions o = new ScanOptions();
            o.setDesiredBarcodeFormats(ScanOptions.QR_CODE);
            o.setPrompt(getString(R.string.scan_prompt));
            o.setBeepEnabled(false);
            o.setOrientationLocked(true);
            scanner.launch(o);
        });
    }

    private void handleCode(String content) {
        if (!applyCode(content)) {
            Toast.makeText(this, R.string.bad_code, Toast.LENGTH_LONG).show();
        }
    }

    /** Config embarquee dans l APK par la forge (assets/safedesk.json). */
    private boolean applyBakedConfig() {
        try (java.io.InputStream in = getAssets().open("safedesk.json")) {
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return applyJson(bo.toString("UTF-8"));
        } catch (Exception e) {
            return false;
        }
    }

    /** Applique un code (safedesk:// ou lien https#fragment). Vrai si reussi. */
    private boolean applyCode(String content) {
        try {
            String json = content.trim();
            if (json.startsWith("https://")) {
                String frag = Uri.parse(json).getFragment();
                if (frag == null) throw new IllegalArgumentException("fragment absent");
                byte[] raw = Base64.decode(frag,
                    Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
                json = new String(raw, StandardCharsets.UTF_8);
            } else if (json.startsWith("safedesk://")) {
                Uri u = Uri.parse(json);
                String data = u.getQueryParameter("data");
                if (data == null) throw new IllegalArgumentException("data manquant");
                byte[] raw = Base64.decode(data,
                    Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
                json = new String(raw, StandardCharsets.UTF_8);
            }
            return applyJson(json);
        } catch (Exception e) {
            return false;
        }
    }

    /** Applique une configuration JSON brute. Vrai si reussie. */
    private boolean applyJson(String json) {
        try {
            JSONObject o = new JSONObject(json);
            String url = o.getString("url");
            String fp = o.optString("fp", "")
                .replace(":", "").toLowerCase(Locale.ROOT);

            Uri parsed = Uri.parse(url);
            String scheme = parsed.getScheme();
            boolean ok =
                "https".equals(scheme)
                || ("http".equals(scheme) && Config.isPrivateHost(parsed.getHost()));
            if (!ok) throw new IllegalArgumentException(
                "https requis (http tolere uniquement vers une adresse privee/VPN)");

            Config.save(this, url, o.getString("user"), o.getString("pass"),
                o.optString("name", getString(R.string.app_name)), fp);
            openDesktop();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private void openDesktop() {
        startActivity(new Intent(this, DesktopActivity.class));
        finish();
    }
}