package org.safedesk.app;

import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
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

/** Accueil TELEPHONE, adaptatif selon le profil (Confort senior / Standard). */
public class HomeActivity extends AppCompatActivity {

    private GridLayout grid;
    private TextView status;
    private boolean senior;
    private final Handler ui = new Handler(Looper.getMainLooper());

    static class Tile { String id, label, icon; Tile(String i,String l,String c){id=i;label=l;icon=c;} }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        senior = Config.isSenior(this);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Color.parseColor("#0F1115"));
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(senior ? 16 : 20), dp(16), dp(senior ? 16 : 20), dp(20));
        scroll.addView(col);


        status = new TextView(this);
        status.setTextColor(Color.parseColor("#8B94A7"));
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, senior ? 18 : 14);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, dp(10), 0, 0);
        col.addView(status);

        grid = new GridLayout(this);
        grid.setColumnCount(2);   // toujours >= 2 colonnes (Confort garde de grandes tuiles)
        grid.setUseDefaultMargins(true);
        LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        gp.topMargin = dp(16);
        col.addView(grid, gp);

        setContentView(scroll);
        render(new ArrayList<>());
        load();
    }

    private void load() {
        status.setText("Chargement\u2026");
        Executors.newSingleThreadExecutor().execute(() -> {
            final List<Tile> tiles = new ArrayList<>();
            try {
                JSONObject o = new JSONObject(httpGet(Config.url(this) + "/safedesk/apps"));
                for (Iterator<String> it = o.keys(); it.hasNext(); ) {
                    String k = it.next();
                    JSONObject a = o.getJSONObject(k);
                    tiles.add(new Tile(k, a.optString("label", k), a.optString("icon", "\u2699\uFE0F")));
                }
            } catch (Exception ignored) {}
            ui.post(() -> {
                render(tiles);
                boolean empty = tiles.isEmpty();
                status.setText(empty ? "Connexion impossible \u2014 touche pour reessayer" : "");
                status.setOnClickListener(empty ? v -> load() : null);
            });
        });
    }

    private void render(List<Tile> tiles) {
        grid.removeAllViews();
        for (Tile t : tiles) {
            TextView tv = tileView(t.icon, t.label, "#1A1F29", "#E8ECF3");
            tv.setOnClickListener(v -> runApp(t));
            grid.addView(tv);
        }
        // Tuile assistant vocal : la page /voice/ du bureau (micro + voix),
        // jeton optionnel du QR passe en #fragment (jamais envoye au serveur).
        TextView vv = tileView("\uD83C\uDF99\uFE0F", "Assistant vocal", "#14322D", "#7EF0DC");
        vv.setOnClickListener(v -> {
            Intent i = new Intent(this, DesktopActivity.class);
            String tok = Config.voice(this);
            i.putExtra("path", "/voice/" + (tok.isEmpty() ? "" : "#t=" + tok));
            startActivity(i);
        });
        grid.addView(vv);

        TextView dv = tileView("\uD83D\uDDA5\uFE0F", "Bureau complet", "#1A1F29", "#E8ECF3");
        dv.setOnClickListener(v -> startActivity(new Intent(this, DesktopActivity.class)));
        grid.addView(dv);


    }

    private void runApp(Tile t) {
        Toast.makeText(this, t.label + "\u2026", Toast.LENGTH_SHORT).show();
        Executors.newSingleThreadExecutor().execute(() -> {
            try { httpGet(Config.url(this) + "/safedesk/run?app=" + t.id); } catch (Exception ignored) {}
            ui.post(() -> startActivity(new Intent(this, DesktopActivity.class)));
        });
    }

    private TextView tileView(String icon, String label, String bg, String fg) {
        TextView tv = new TextView(this);
        tv.setText(icon + "\n" + label);
        tv.setGravity(Gravity.CENTER);
        tv.setTextColor(Color.parseColor(fg));
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, senior ? 21 : 17);
        tv.setLineSpacing(dp(senior ? 8 : 2), 1f);
        tv.setBackgroundColor(Color.parseColor(bg));
        GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
        lp.width = 0;
        lp.height = dp(senior ? 160 : 130);
        lp.columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1, 1f);
        int m = dp(senior ? 10 : 8);
        lp.setMargins(m, m, m, m);
        tv.setLayoutParams(lp);
        return tv;
    }

    private String httpGet(String urlStr) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(urlStr).openConnection();
        String auth = Config.user(this) + ":" + Config.pass(this);
        c.setRequestProperty("Authorization", "Basic " +
                Base64.encodeToString(auth.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
        c.setConnectTimeout(8000); c.setReadTimeout(8000);
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