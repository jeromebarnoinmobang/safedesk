package org.safedesk.app;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.animation.AnimationUtils;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.List;
import java.util.Locale;

/** Premier ecran : un petit personnage dit bonjour et apprend a la personne
 *  qu'elle peut PARLER a l'appareil. "Tu peux me dire bonjour." */
public class WelcomeActivity extends AppCompatActivity {

    private TextToSpeech tts;
    private boolean ttsReady;
    private TextView bubble;

    private static final String HELLO =
            "Bonjour ! Je suis la pour t'aider. Tu peux me parler. Dis-moi : bonjour !";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setBackgroundColor(Color.parseColor("#0F1115"));
        col.setGravity(Gravity.CENTER_HORIZONTAL);
        col.setPadding(dp(24), dp(36), dp(24), dp(24));

        ImageView m = new ImageView(this);
        m.setImageResource(R.drawable.mascotte);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(180), dp(180));
        ip.topMargin = dp(20);
        m.setLayoutParams(ip);
        col.addView(m);
        m.startAnimation(AnimationUtils.loadAnimation(this, android.R.anim.fade_in));

        bubble = new TextView(this);
        bubble.setText("Bonjour !\nTu peux me parler.\nDis-moi : \u00AB Bonjour \u00BB \uD83D\uDC4B");
        bubble.setTextColor(Color.WHITE);
        bubble.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        bubble.setGravity(Gravity.CENTER);
        bubble.setLineSpacing(dp(6), 1f);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bp.topMargin = dp(28);
        bubble.setLayoutParams(bp);
        col.addView(bubble);

        LinearLayout spacer = new LinearLayout(this);
        spacer.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        col.addView(spacer);

        Button talk = big("\uD83C\uDFA4  Parle-moi", "#14B8A6", "#0F1115", 26, 88);
        talk.setOnClickListener(v -> listen());
        col.addView(talk);

        Button cont = big("Continuer  \u2192", "#1A1F29", "#E8ECF3", 20, 64);
        LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cp.topMargin = dp(12);
        cont.setLayoutParams(cp);
        cont.setOnClickListener(v -> goHome());
        col.addView(cont);

        setContentView(col);

        tts = new TextToSpeech(this, s -> {
            if (s == TextToSpeech.SUCCESS) {
                tts.setLanguage(Locale.FRENCH);
                ttsReady = true;
                new Handler(Looper.getMainLooper()).postDelayed(this::sayHello, 600);
            }
        });
    }

    private void sayHello() {
        if (ttsReady) tts.speak(HELLO, TextToSpeech.QUEUE_FLUSH, null, "hi");
    }

    private void listen() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this,
                    new String[]{Manifest.permission.RECORD_AUDIO}, 1);
            return;
        }
        if (ttsReady) tts.speak("Je t'ecoute.", TextToSpeech.QUEUE_FLUSH, null, "l");
        Intent i = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "fr-FR");
        try { startActivityForResult(i, 7); } catch (Exception e) { goTutos(); }
    }

    @Override
    protected void onActivityResult(int rq, int rs, Intent data) {
        super.onActivityResult(rq, rs, data);
        if (rq == 7 && rs == RESULT_OK && data != null) {
            List<String> r = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
            String said = (r != null && !r.isEmpty()) ? r.get(0).toLowerCase(Locale.FRENCH) : "";
            if (said.contains("bonjour") || said.contains("salut") || said.contains("coucou")) {
                bubble.setText("Bonjour a toi ! \uD83D\uDE0A\nBravo, tu m'as parle.\nQue veux-tu faire ?");
                if (ttsReady) tts.speak(
                        "Bonjour a toi ! Bravo, tu m'as parle. Maintenant, je vais te montrer.",
                        TextToSpeech.QUEUE_FLUSH, null, "ok");
                new Handler(Looper.getMainLooper()).postDelayed(this::goTutos, 3200);
            } else {
                goTutos();
            }
        }
    }

    @Override
    public void onRequestPermissionsResult(int rq, String[] p, int[] g) {
        super.onRequestPermissionsResult(rq, p, g);
        if (rq == 1 && g.length > 0 && g[0] == PackageManager.PERMISSION_GRANTED) listen();
    }

    private void goTutos() { startActivity(new Intent(this, TutoActivity.class)); finish(); }
    private void goHome()  { startActivity(new Intent(this, HomeActivity.class)); finish(); }

    private Button big(String t, String bg, String fg, int sp, int h) {
        Button b = new Button(this);
        b.setText(t); b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        b.setTextColor(Color.parseColor(fg));
        b.setBackgroundColor(Color.parseColor(bg));
        b.setMinHeight(dp(h));
        b.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return b;
    }

    @Override protected void onDestroy() {
        if (tts != null) { tts.stop(); tts.shutdown(); }
        super.onDestroy();
    }
    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }
}