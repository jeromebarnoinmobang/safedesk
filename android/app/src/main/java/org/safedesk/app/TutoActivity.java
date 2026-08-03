package org.safedesk.app;

import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.speech.tts.TextToSpeech;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** Aide vocale + tutoriels rejouables. La voix est la porte d entree. */
public class TutoActivity extends AppCompatActivity {

    static class Tuto { String title, icon; List<String> steps = new ArrayList<>(); }

    private final List<Tuto> tutos = new ArrayList<>();
    private Tuto current;
    private int step;
    private Speaker speaker;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        loadTutos();
        speaker = new Speaker(this);
        new Handler(Looper.getMainLooper()).postDelayed(() ->
                speak("Bonjour. Tu peux me parler, ou choisir dans la liste."), 500);
        showList();
    }

    private void speak(String s) { speaker.play(s, null); }

    private void loadTutos() {
        try {
            InputStream in = getAssets().open("tutos.json");
            byte[] buf = new byte[in.available()];
            in.read(buf); in.close();
            JSONArray arr = new JSONObject(new String(buf, StandardCharsets.UTF_8))
                    .getJSONArray("tutos");
            for (int i = 0; i < arr.length(); i++) {
                JSONObject o = arr.getJSONObject(i);
                Tuto t = new Tuto();
                t.title = o.getString("title");
                t.icon = o.optString("icon", "\uD83C\uDF93");
                JSONArray st = o.getJSONArray("steps");
                for (int j = 0; j < st.length(); j++) t.steps.add(st.getString(j));
                tutos.add(t);
            }
        } catch (Exception ignored) {}
    }

    // ----- liste + bouton Parle-moi -----
    private void showList() {
        current = null;
        ScrollView sc = new ScrollView(this);
        sc.setBackgroundColor(Color.parseColor("#0F1115"));
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(20), dp(24), dp(20), dp(24));
        sc.addView(col);

        Button talk = bigButton("\uD83C\uDFA4  Parle-moi", "#14B8A6", "#0F1115");
        talk.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        talk.setMinHeight(dp(84));
        talk.setOnClickListener(v -> startListening());
        col.addView(talk);

        TextView hint = new TextView(this);
        hint.setText("...ou choisis ci-dessous.\nTu peux recommencer autant de fois que tu veux.");
        hint.setTextColor(Color.parseColor("#8B94A7"));
        hint.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        hint.setGravity(Gravity.CENTER);
        hint.setPadding(0, dp(16), 0, dp(18));
        col.addView(hint);

        for (Tuto tu : tutos) col.addView(tutoCard(tu));
        setContentView(sc);
    }

    private LinearLayout tutoCard(Tuto tu) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setBackgroundColor(Color.parseColor("#1A1F29"));
        card.setPadding(dp(20), dp(24), dp(20), dp(24));
        card.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(14);
        card.setLayoutParams(lp);
        TextView ic = new TextView(this);
        ic.setText(tu.icon);
        ic.setTextSize(TypedValue.COMPLEX_UNIT_SP, 34);
        ic.setPadding(0, 0, dp(18), 0);
        card.addView(ic);
        TextView tv = new TextView(this);
        tv.setText(tu.title);
        tv.setTextColor(Color.WHITE);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        card.addView(tv);
        card.setOnClickListener(v -> startTuto(tu));
        return card;
    }

    // ----- voix : ecoute -> trouve un tuto -----
    private void startListening() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this,
                    new String[]{Manifest.permission.RECORD_AUDIO}, 1);
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            speak("La reconnaissance vocale n'est pas disponible sur ce telephone.");
            return;
        }
        speak("Je t'ecoute.");
        Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "fr-FR");
        i.putExtra(RecognizerIntent.EXTRA_PROMPT, "Dis ce que tu veux faire");
        try { startActivityForResult(i, 42); }
        catch (Exception e) { speak("Je ne peux pas ecouter pour le moment."); }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == 42 && res == RESULT_OK && data != null) {
            List<String> r = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
            String said = (r != null && !r.isEmpty()) ? r.get(0).toLowerCase(Locale.FRENCH) : "";
            Tuto match = findTuto(said);
            if (match != null) { speak("D'accord, on regarde : " + match.title); startTuto(match); }
            else speak("Je n'ai pas compris. Touche une grande case pour choisir.");
        }
    }

    private Tuto findTuto(String said) {
        for (Tuto t : tutos) {
            for (String w : t.title.toLowerCase(Locale.FRENCH).split(" ")) {
                if (w.length() >= 4 && said.contains(w)) return t;
            }
        }
        if (said.contains("photo")) return byTitle("photo");
        if (said.contains("mail") || said.contains("mel") || said.contains("message")) return byTitle("ecrire");
        if (said.contains("retour") || said.contains("accueil")) return byTitle("revenir");
        return null;
    }
    private Tuto byTitle(String key) {
        for (Tuto t : tutos) if (t.title.toLowerCase(Locale.FRENCH).contains(key)) return t;
        return null;
    }

    @Override
    public void onRequestPermissionsResult(int rq, String[] p, int[] g) {
        super.onRequestPermissionsResult(rq, p, g);
        if (rq == 1 && g.length > 0 && g[0] == PackageManager.PERMISSION_GRANTED) startListening();
        else Toast.makeText(this, "Micro refuse", Toast.LENGTH_SHORT).show();
    }

    // ----- lecture pas a pas (avec lecture vocale) -----
    private void startTuto(Tuto t) { current = t; step = 0; showStep(); }

    private void showStep() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#0F1115"));
        root.setPadding(dp(24), dp(28), dp(24), dp(24));

        TextView prog = new TextView(this);
        prog.setText(current.icon + "   Etape " + (step + 1) + " sur " + current.steps.size());
        prog.setTextColor(Color.parseColor("#2DD4BF"));
        prog.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        prog.setGravity(Gravity.CENTER);
        root.addView(prog);

        LinearLayout mid = new LinearLayout(this);
        mid.setOrientation(LinearLayout.VERTICAL);
        mid.setGravity(Gravity.CENTER);
        mid.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        TextView instr = new TextView(this);
        instr.setText(current.steps.get(step));
        instr.setTextColor(Color.WHITE);
        instr.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        instr.setGravity(Gravity.CENTER);
        instr.setLineSpacing(dp(6), 1f);
        mid.addView(instr);
        Button replay = bigButton("\uD83D\uDD0A  Reecouter", "#1A1F29", "#E8ECF3");
        replay.setMinHeight(dp(52));
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rlp.topMargin = dp(20);
        replay.setLayoutParams(rlp);
        replay.setOnClickListener(v -> speak(current.steps.get(step)));
        mid.addView(replay);
        root.addView(mid);

        boolean last = step == current.steps.size() - 1;
        Button next = bigButton(last ? "\u2713  J'ai fini" : "Suivant  \u2192", "#2DD4BF", "#0F1115");
        next.setOnClickListener(v -> { if (last) showList(); else { step++; showStep(); } });
        root.addView(next);

        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, dp(12), 0, 0);
        Button prev = bigButton("\u2190  Precedent", "#1A1F29", "#E8ECF3");
        prev.setEnabled(step > 0); prev.setAlpha(step > 0 ? 1f : 0.4f);
        LinearLayout.LayoutParams h1 = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        h1.rightMargin = dp(8); prev.setLayoutParams(h1);
        prev.setOnClickListener(v -> { if (step > 0) { step--; showStep(); } });
        Button quit = bigButton("Quitter", "#1A1F29", "#8B94A7");
        LinearLayout.LayoutParams h2 = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        h2.leftMargin = dp(8); quit.setLayoutParams(h2);
        quit.setOnClickListener(v -> showList());
        row.addView(prev); row.addView(quit);
        root.addView(row);

        setContentView(root);
        speak(current.steps.get(step));   // lecture vocale automatique
    }

    private Button bigButton(String text, String bg, String fg) {
        Button b = new Button(this);
        b.setText(text); b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        b.setTextColor(Color.parseColor(fg));
        b.setBackgroundColor(Color.parseColor(bg));
        b.setMinHeight(dp(64));
        b.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return b;
    }

    @Override
    public void onBackPressed() {
        if (current != null) showList(); else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (speaker != null) speaker.shutdown();
        super.onDestroy();
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }
}