package org.safedesk.app;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.util.Base64;

import java.net.URLEncoder;
import java.util.HashMap;
import java.util.Locale;

/** Fait parler l'app avec la voix du SERVEUR (/safedesk/tts). Repli PARESSEUX : TTS systeme. */
class Speaker {
    interface Done { void onDone(); }

    private final Context ctx;
    private MediaPlayer mp;
    private TextToSpeech fallback;
    private boolean fbReady;
    private String pendingText;
    private Done pendingDone;

    Speaker(Context c) { ctx = c; }

    void play(String text, Done done) {
        release();
        try {
            String url = Config.url(ctx) + "/safedesk/tts?text=" + URLEncoder.encode(text, "UTF-8");
            HashMap<String, String> h = new HashMap<>();
            String auth = Config.user(ctx) + ":" + Config.pass(ctx);
            h.put("Authorization", "Basic " + Base64.encodeToString(auth.getBytes("UTF-8"), Base64.NO_WRAP));
            mp = new MediaPlayer();
            mp.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build());
            mp.setDataSource(ctx, Uri.parse(url), h);
            mp.setOnPreparedListener(MediaPlayer::start);
            mp.setOnCompletionListener(m -> { release(); if (done != null) done.onDone(); });
            mp.setOnErrorListener((m, a, b) -> { release(); fb(text, done); return true; });
            mp.prepareAsync();
        } catch (Exception e) {
            fb(text, done);
        }
    }

    // repli cree seulement si besoin
    private void fb(String text, Done done) {
        if (fbReady) { speakFb(text, done); return; }
        pendingText = text; pendingDone = done;
        if (fallback == null) {
            fallback = new TextToSpeech(ctx, s -> {
                if (s == TextToSpeech.SUCCESS) {
                    fallback.setLanguage(Locale.FRENCH);
                    fbReady = true;
                    if (pendingText != null) { speakFb(pendingText, pendingDone); pendingText = null; pendingDone = null; }
                } else if (pendingDone != null) {
                    new Handler(Looper.getMainLooper()).post(pendingDone::onDone);
                }
            });
        }
    }

    private void speakFb(String text, Done done) {
        fallback.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            public void onStart(String i) {}
            public void onError(String i) { if (done != null) new Handler(Looper.getMainLooper()).post(done::onDone); }
            public void onDone(String i) { if (done != null) new Handler(Looper.getMainLooper()).post(done::onDone); }
        });
        fallback.speak(text, TextToSpeech.QUEUE_FLUSH, null, "fb");
    }

    void stop() { release(); }
    private void release() {
        if (mp != null) { try { mp.reset(); mp.release(); } catch (Exception e) {} mp = null; }
    }
    void shutdown() {
        release();
        if (fallback != null) { try { fallback.stop(); fallback.shutdown(); } catch (Exception e) {} }
    }
}