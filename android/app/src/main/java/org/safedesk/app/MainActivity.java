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
        if (Config.isConfigured(this)) { openDesktop(); return; }
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
        try {
            String json = content.trim();
            if (json.startsWith("safedesk://")) {
                Uri u = Uri.parse(json);
                String data = u.getQueryParameter("data");
                if (data == null) throw new IllegalArgumentException("data manquant");
                byte[] raw = Base64.decode(data,
                    Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
                json = new String(raw, StandardCharsets.UTF_8);
            }
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
        } catch (Exception e) {
            Toast.makeText(this, R.string.bad_code, Toast.LENGTH_LONG).show();
        }
    }

    private void openDesktop() {
        startActivity(new Intent(this, DesktopActivity.class));
        finish();
    }
}