package org.safedesk.app;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.media.AudioManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.speech.RecognizerIntent;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.animation.Animation;
import android.view.animation.TranslateAnimation;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.List;
import java.util.Locale;

/** Accueil "super assiste" : chaton qui parle. Si le son est coupe/bas,
 *  il fait de GRANDS SIGNES ecrits pour dire de monter le son, et le monte. */
public class WelcomeActivity extends AppCompatActivity {

    private TextToSpeech tts;
    private AudioManager am;
    private boolean ttsReady, soundReady, greeted;
    private TextView bubble;
    private ImageView kitten;
    private Button talk;

    private static final String HELLO =
            "Bonjour ! Je suis la pour t'aider. Tu peux me parler. Dis-moi : bonjour !";
    private static final String BUBBLE_HELLO =
            "Bonjour !\nTu peux me parler.\nDis-moi : \u00AB Bonjour \u00BB \uD83D\uDC4B";
    private static final String BUBBLE_SOUND =
            "\uD83D\uDD08 Le son est trop bas !\n\nMonte le son pour m'entendre :\nappuie sur les boutons de VOLUME,\nsur le cote du telephone. \uD83D\uDC49";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setBackgroundColor(Color.parseColor("#0F1115"));
        col.setGravity(Gravity.CENTER_HORIZONTAL);
        col.setPadding(dp(24), dp(36), dp(24), dp(24));

        kitten = new ImageView(this);
        kitten.setImageResource(R.drawable.mascotte);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(180), dp(180));
        ip.topMargin = dp(16);
        kitten.setLayoutParams(ip);
        col.addView(kitten);

        bubble = new TextView(this);
        bubble.setTextColor(Color.WHITE);
        bubble.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        bubble.setGravity(Gravity.CENTER);
        bubble.setLineSpacing(dp(6), 1f);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bp.topMargin = dp(24);
        bubble.setLayoutParams(bp);
        col.addView(bubble);

        LinearLayout spacer = new LinearLayout(this);
        spacer.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        col.addView(spacer);

        talk = big("\uD83C\uDFA4  Parle-moi", "#14B8A6", "#0F1115", 26, 88);
        talk.setOnClickListener(v -> onPrimary());
        col.addView(talk);

        Button cont = big("Continuer  \u2192", "#1A1F29", "#E8ECF3", 20, 64);
        LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cp.topMargin = dp(12);
        cont.setLayoutParams(cp);
        cont.setOnClickListener(v -> goHome());
        col.addView(cont);
        setContentView(col);

        // moteur Google explicite (le defaut est parfois nul)
        tts = new TextToSpeech(this, s -> {
            if (s == TextToSpeech.SUCCESS) {
                tts.setLanguage(Locale.FRENCH);
                ttsReady = true;
                tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                    public void onStart(String id) {}
                    public void onError(String id) {}
                    public void onDone(String id) {
                        if ("hi".equals(id)) runOnUiThread(WelcomeActivity.this::promptMicThenListen);
                        else if ("perm".equals(id)) runOnUiThread(() ->
                                ActivityCompat.requestPermissions(WelcomeActivity.this,
                                        new String[]{Manifest.permission.RECORD_AUDIO}, 1));
                    }
                });
                runOnUiThread(WelcomeActivity.this::maybeGreet);
            }
        }, "com.google.android.tts");

        ensureSound();
    }

    // ----- robustesse audio -----
    private void ensureSound() {
        int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        int vol = am.getStreamVolume(AudioManager.STREAM_MUSIC);
        if (vol >= Math.max(1, (int) (max * 0.25))) { soundOk(); return; }
        // trop bas : on tente de monter nous-memes...
        try { am.setStreamVolume(AudioManager.STREAM_MUSIC, (int) (max * 0.7),
                AudioManager.FLAG_SHOW_UI); } catch (Exception ignored) {}
        vol = am.getStreamVolume(AudioManager.STREAM_MUSIC);
        if (vol >= Math.max(1, (int) (max * 0.25))) { soundOk(); return; }
        // ...sinon GRANDS SIGNES ecrits
        bubble.setText(BUBBLE_SOUND);
        talk.setText("\uD83D\uDD0A  Monter le son");
        shake(kitten);
    }

    private void soundOk() {
        soundReady = true;
        bubble.setText(BUBBLE_HELLO);
        talk.setText("\uD83C\uDFA4  Parle-moi");
        maybeGreet();
    }

    private void onPrimary() {
        if (!soundReady) {   // en mode "monter le son"
            int max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            try { am.setStreamVolume(AudioManager.STREAM_MUSIC, (int) (max * 0.7),
                    AudioManager.FLAG_SHOW_UI); } catch (Exception ignored) {}
            ensureSound();
        } else {
            listen();
        }
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
        boolean r = super.onKeyDown(code, e);
        if (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN) {
            new Handler(Looper.getMainLooper()).postDelayed(() -> { if (!soundReady) ensureSound(); }, 250);
        }
        return r;
    }

    private void shake(android.view.View v) {
        TranslateAnimation a = new TranslateAnimation(-dp(10), dp(10), 0, 0);
        a.setDuration(120); a.setRepeatCount(Animation.INFINITE);
        a.setRepeatMode(Animation.REVERSE);
        v.startAnimation(a);
    }

    private void maybeGreet() {
        if (ttsReady && soundReady && !greeted) {
            greeted = true;
            if (kitten.getAnimation() != null) kitten.clearAnimation();
            tts.speak(HELLO, TextToSpeech.QUEUE_FLUSH, null, "hi");
        }
    }

    private void promptMicThenListen() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) { listen(); return; }
        bubble.setText("Pour que tu puisses me repondre,\nton telephone va demander\nl'autorisation du micro.\n\nTouche \u00AB Autoriser \u00BB \uD83D\uDC4D");
        if (ttsReady) tts.speak(
                "Pour que tu puisses me repondre, ton telephone va te demander l'autorisation du micro. Touche : Autoriser.",
                TextToSpeech.QUEUE_FLUSH, null, "perm");
        else ActivityCompat.requestPermissions(this,
                new String[]{Manifest.permission.RECORD_AUDIO}, 1);
    }

    private void listen() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) { promptMicThenListen(); return; }
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
                if (ttsReady) tts.speak("Bonjour a toi ! Bravo, tu m'as parle. Je vais te montrer.",
                        TextToSpeech.QUEUE_FLUSH, null, "ok");
                new Handler(Looper.getMainLooper()).postDelayed(this::goTutos, 3200);
            } else goTutos();
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