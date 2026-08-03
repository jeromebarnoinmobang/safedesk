package org.safedesk.app;

import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONObject;

import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.Executors;

/** Accueil TELEPHONE : grandes tuiles. Chaque tuile = une appli ouverte cote serveur. */
public class HomeActivity extends AppCompatActivity {

    private GridLayout grid;
    private final Handler ui = new Handler(Looper.getMainLooper());

    static class Tile { String id, label, icon; Tile(String i, String l, String c){id=i;label=l;icon=c;} }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.parseColor("#0F1115"));
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(20), dp(28), dp(20), dp(20));
        scroll.addView(col);

        TextView title = new TextView(this);
        title.setText(Config.name(this));
        title.setTextColor(Color.parseColor("#E8ECF3"));
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        title.setGravity(Gravity.CENTER);
        col.addView(title);

        grid = new GridLayout(this);
        grid.setColumnCount(2);
        grid.setUseDefaultMargins(true);
        LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        gp.topMargin = dp(20);
        col.addView(grid, gp);

        // Tuile "Bureau complet" (mode expert) toujours presente
        TextView deskTile = tileView(new Tile("__desktop__", "Bureau complet", "\uD83D\uDDA5\uFE0F"));
        deskTile.setOnClickListener(v -> {
            startActivity(new Intent(this, DesktopActivity.class));
        });
        grid.addView(deskTile);

        setContentView(scroll);
        loadTiles();
    }

    private void loadTiles() {
        Executors.newSingleThreadExecutor().execute(() -> {
            final List<Tile> tiles = new ArrayList<>();
            try {
                String json = httpGet(Config.url(this) + "/safedesk/apps");
                JSONObject o = new JSONObject(json);
                for (Iterator<String> it = o.keys(); it.hasNext(); ) {
                    String k = it.next();
                    JSONObject a = o.getJSONObject(k);
                    tiles.add(new Tile(k, a.optString("label", k), a.optString("icon", "\u2699\uFE0F")));
                }
            } catch (Exception ignored) {}
            ui.post(() -> {
                for (Tile t : tiles) {
                    TextView tv = tileView(t);
                    tv.setOnClickListener(v -> runApp(t));
                    grid.addView(tv);
                }
            });
        });
    }

    private void runApp(Tile t) {
        Toast.makeText(this, t.label + "\u2026", Toast.LENGTH_SHORT).show();
        Executors.newSingleThreadExecutor().execute(() -> {
            try { httpGet(Config.url(this) + "/safedesk/run?app=" + t.id); } catch (Exception ignored) {}
            ui.post(() -> startActivity(new Intent(this, DesktopActivity.class)));
        });
    }

    private TextView tileView(Tile t) {
        TextView tv = new TextView(this);
        tv.setText(t.icon + "\n" + t.label);
        tv.setGravity(Gravity.CENTER);
        tv.setTextColor(Color.parseColor("#E8ECF3"));
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        tv.setBackgroundColor(Color.parseColor("#1A1F29"));
        GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
        lp.width = 0;
        lp.height = dp(130);
        lp.columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1, 1f);
        lp.setMargins(dp(8), dp(8), dp(8), dp(8));
        tv.setLayoutParams(lp);
        return tv;
    }

    private String httpGet(String urlStr) throws IOException {
        URL url = new URL(urlStr);
        HttpURLConnection c = (HttpURLConnection) url.openConnection();
        String auth = Config.user(this) + ":" + Config.pass(this);
        c.setRequestProperty("Authorization", "Basic " +
                Base64.encodeToString(auth.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
        c.setConnectTimeout(8000);
        c.setReadTimeout(8000);
        java.io.InputStream in = c.getInputStream();
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[4096]; int n;
        while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        in.close();
        return bo.toString("UTF-8");
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }
}