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

/** Le bureau streame, plein ecran, auth automatique, ecran maintenu allume. */
public class DesktopActivity extends AppCompatActivity {

    private WebView web;
    private int authTries = 0;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        setContentView(web);

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
                    if (request.getOrigin() != null && host != null
                            && host.equals(request.getOrigin().getHost())) {
                        request.grant(request.getResources());
                    } else {
                        request.deny();
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
                if (authTries++ < 8) {
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
        web.loadUrl(Config.url(this));

        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override public void handleOnBackPressed() { finish(); }  // retour a l accueil a tuiles
        });
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
}