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

/** Fait parler l'app avec la voix du SERVEUR (/safedesk/tts). Repli : TTS systeme. */
class Speaker {
    interface Done { void onDone(); }

    private final Context ctx;
    private MediaPlayer mp;
    private TextToSpeech fallback;
    private boolean fbReady;

    Speaker(Context c) {
        ctx = c;
        fallback = new TextToSpeech(c, s -> {
            if (s == TextToSpeech.SUCCESS) { fallback.setLanguage(Locale.FRENCH); fbReady = true; }
        }, "com.google.android.tts");
    }

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

    private void fb(String text, Done done) {
        if (fbReady) {
            fallback.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                public void onStart(String i) {}
                public void onError(String i) {}
                public void onDone(String i) {
                    if (done != null) new Handler(Looper.getMainLooper()).post(done::onDone);
                }
            });
            fallback.speak(text, TextToSpeech.QUEUE_FLUSH, null, "fb");
        } else if (done != null) {
            new Handler(Looper.getMainLooper()).postDelayed(done::onDone, 1200);
        }
    }

    void stop() { release(); }
    private void release() {
        if (mp != null) { try { mp.reset(); mp.release(); } catch (Exception e) {} mp = null; }
    }
    void shutdown() {
        release();
        if (fallback != null) { fallback.stop(); fallback.shutdown(); }
    }
}