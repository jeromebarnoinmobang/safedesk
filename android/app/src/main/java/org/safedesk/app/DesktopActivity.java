package org.safedesk.app;

import android.annotation.SuppressLint;
import android.content.Intent;
import android.net.http.SslCertificate;
import android.net.http.SslError;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.HttpAuthHandler;
import android.webkit.PermissionRequest;
import android.webkit.SslErrorHandler;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.FrameLayout;
import android.view.Gravity;
import android.util.TypedValue;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.WindowCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import java.security.MessageDigest;
import java.util.Locale;

/** Le bureau streame, plein ecran, auth automatique, ecran maintenu allume.
 *  Extra Intent optionnel "path" : sous-chemin a ouvrir sur le meme bureau
 *  (ex. "/voice/" = page assistant vocal), defaut "" = bureau complet. */
public class DesktopActivity extends AppCompatActivity {

    private static final int REQ_MIC = 71;

    private WebView web;
    private int authTries = 0;
    private PermissionRequest pendingPermRequest;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        FrameLayout root = new FrameLayout(this);
        root.addView(web, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        Button home = new Button(this);
        home.setText("\u2302");                       // maison
        home.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        home.setBackgroundColor(0xCC14B8A6);
        home.setTextColor(0xFF0F1115);
        int sz = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 52,
                getResources().getDisplayMetrics());
        int mg = (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 14,
                getResources().getDisplayMetrics());
        FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(sz, sz);
        hp.gravity = Gravity.BOTTOM | Gravity.START;
        hp.setMargins(mg, mg, mg, mg);
        home.setLayoutParams(hp);
        // Retour aux tuiles. En mode tablette, le bureau est lance DIRECTEMENT
        // (racine de la tache) : un finish() fermerait l app — on ouvre l accueil.
        home.setOnClickListener(v -> {
            if (isTaskRoot()) startActivity(new Intent(this, HomeActivity.class));
            finish();
        });
        root.addView(home);

        setContentView(root);

        // Session a l echelle du TELEPHONE : on neutralise le devicePixelRatio pour
        // que le stream demande une resolution logique (~400pt de large) -> interface
        // grande et tapable. Le PC, lui, garde sa pleine resolution.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(web,
                "(function(){try{Object.defineProperty(window,'devicePixelRatio'," +
                "{get:function(){return 1;},configurable:true});}catch(e){}})();",
                new java.util.HashSet<>(java.util.Arrays.asList("*")));
        }

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setSupportZoom(false);

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> {
                    String host = android.net.Uri.parse(Config.url(DesktopActivity.this)).getHost();
                    String origin = request.getOrigin() == null ? null : request.getOrigin().getHost();
                    if (origin == null || host == null || !sameBaseDomain(host, origin)) {
                        request.deny();
                        return;
                    }
                    // On ne grante QUE le micro (la page /voice/ n a besoin de
                    // rien d autre) — jamais request.getResources() en bloc.
                    boolean wantsAudio = false;
                    for (String r : request.getResources()) {
                        if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(r)) wantsAudio = true;
                    }
                    if (!wantsAudio) { request.deny(); return; }
                    if (androidx.core.content.ContextCompat.checkSelfPermission(
                            DesktopActivity.this, android.Manifest.permission.RECORD_AUDIO)
                            == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        request.grant(new String[]{ PermissionRequest.RESOURCE_AUDIO_CAPTURE });
                    } else {
                        // le grant WebView est sans effet tant que l app n a pas
                        // la permission Android : on la demande, reponse dans
                        // onRequestPermissionsResult.
                        pendingPermRequest = request;
                        androidx.core.app.ActivityCompat.requestPermissions(DesktopActivity.this,
                            new String[]{ android.Manifest.permission.RECORD_AUDIO }, REQ_MIC);
                    }
                });
            }
        });

        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                // le chargement a abouti : l auth est bonne, on rearme le garde-fou
                authTries = 0;
            }

            @Override
            public void onReceivedHttpAuthRequest(WebView view, HttpAuthHandler handler,
                                                  String host, String realm) {
                String cfgHost = android.net.Uri.parse(Config.url(DesktopActivity.this)).getHost();
                if (authTries++ < 8 && cfgHost != null && sameBaseDomain(cfgHost, host)) {
                    handler.proceed(Config.user(DesktopActivity.this),
                                    Config.pass(DesktopActivity.this));
                } else {
                    handler.cancel();
                }
            }

            /**
             * Sans nom de domaine, le serveur presente un certificat auto-signe :
             * on ne l accepte QUE si son empreinte SHA-256 est exactement celle
             * epinglee dans le QR. Sinon, refus systematique.
             */
            @Override
            public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                String pinned = Config.fp(DesktopActivity.this);
                if (!pinned.isEmpty() && pinned.equals(sha256Of(error.getCertificate()))) {
                    handler.proceed();
                } else {
                    handler.cancel();
                    Toast.makeText(DesktopActivity.this, R.string.ssl_refused,
                        Toast.LENGTH_LONG).show();
                }
            }
        });

        hideBars();
        String abs = getIntent().getStringExtra("url");
        String path = getIntent().getStringExtra("path");
        // "url" (absolue, https) = page servie hors du bureau streame (OpenWork,
        // assistant vocal) mais ouverte dans CETTE webview : micro et auth du device.
        if (abs != null && abs.startsWith("https://")) web.loadUrl(abs);
        else web.loadUrl(Config.url(this) + (path == null ? "" : path));

        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override public void handleOnBackPressed() { finish(); }  // retour a l accueil a tuiles
        });
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        super.onRequestPermissionsResult(code, perms, results);
        if (code != REQ_MIC || pendingPermRequest == null) return;
        PermissionRequest req = pendingPermRequest;
        pendingPermRequest = null;
        boolean granted = results.length > 0
                && results[0] == android.content.pm.PackageManager.PERMISSION_GRANTED;
        try {
            if (granted) req.grant(new String[]{ PermissionRequest.RESOURCE_AUDIO_CAPTURE });
            else {
                req.deny();
                Toast.makeText(this, R.string.mic_refused, Toast.LENGTH_LONG).show();
            }
        } catch (Exception ignored) { /* requete WebView deja invalidee */ }
    }

    private static String sha256Of(SslCertificate cert) {
        try {
            Bundle state = SslCertificate.saveState(cert);
            byte[] der = state.getByteArray("x509-certificate");
            if (der == null) return "";
            byte[] d = MessageDigest.getInstance("SHA-256").digest(der);
            StringBuilder sb = new StringBuilder(d.length * 2);
            for (byte b : d) sb.append(String.format(Locale.ROOT, "%02x", b));
            return sb.toString();
        } catch (Exception e) {
            return "";
        }
    }

    private void hideBars() {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        WindowInsetsControllerCompat c =
            new WindowInsetsControllerCompat(getWindow(), web);
        c.hide(WindowInsetsCompat.Type.systemBars());
        c.setSystemBarsBehavior(
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
    }

    private void confirmQuit() {
        new AlertDialog.Builder(this)
            .setTitle(R.string.quit_title)
            .setPositiveButton(R.string.quit_yes, (d, w) -> finish())
            .setNegativeButton(R.string.quit_no, null)
            .setNeutralButton(R.string.quit_forget, (d, w) -> {
                Config.clear(this);
                startActivity(new Intent(this, MainActivity.class));
                finish();
            })
            .show();
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }

    /** meme domaine enregistrable (desktop.mobang.fr ~ voice.mobang.fr) :
     *  les credentials et le micro ne sortent jamais du domaine du bureau. */
    private static boolean sameBaseDomain(String a, String b) {
        String[] pa = a.split("\\."), pb = b.split("\\.");
        if (pa.length < 2 || pb.length < 2) return a.equals(b);
        return pa[pa.length-1].equals(pb[pb.length-1]) && pa[pa.length-2].equals(pb[pb.length-2]);
    }
}