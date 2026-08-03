package org.safedesk.app;

import android.annotation.SuppressLint;
import android.content.Intent;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.HttpAuthHandler;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

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
            public void onReceivedHttpAuthRequest(WebView view, HttpAuthHandler handler,
                                                  String host, String realm) {
                if (authTries++ < 3) {
                    handler.proceed(Config.user(DesktopActivity.this),
                                    Config.pass(DesktopActivity.this));
                } else {
                    handler.cancel();
                }
            }
        });

        hideBars();
        web.loadUrl(Config.url(this));

        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override public void handleOnBackPressed() { confirmQuit(); }
        });
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