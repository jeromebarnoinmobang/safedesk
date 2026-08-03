package org.safedesk.app;

import android.content.Context;
import android.content.SharedPreferences;

/** Configuration locale (issue du QR scanne). Aucune valeur en dur. */
final class Config {
    private static final String PREFS = "safedesk";

    private Config() {}

    private static SharedPreferences p(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isConfigured(Context c) { return p(c).contains("url"); }

    static void save(Context c, String url, String user, String pass, String name, String fp) {
        p(c).edit().putString("url", url).putString("user", user)
            .putString("pass", pass).putString("name", name)
            .putString("fp", fp == null ? "" : fp).apply();
    }

    static void clear(Context c) { p(c).edit().clear().apply(); }

    static String url(Context c)  { return p(c).getString("url", ""); }
    static String user(Context c) { return p(c).getString("user", ""); }
    static String pass(Context c) { return p(c).getString("pass", ""); }
    static String name(Context c) { return p(c).getString("name", "SafeDesk"); }

    // Profil d affichage choisi a l installation : "senior" (Confort) ou "standard".
    static boolean hasProfile(Context c) { return p(c).contains("profile"); }
    static String profile(Context c) { return p(c).getString("profile", "standard"); }
    static boolean isSenior(Context c) { return "senior".equals(profile(c)); }
    static void setProfile(Context c, String v) { p(c).edit().putString("profile", v).apply(); }
    /** Empreinte SHA-256 (hex, sans ':') d un certificat auto-signe epingle. Vide sinon. */
    static String fp(Context c)   { return p(c).getString("fp", ""); }

    /**
     * Hote "prive" : IP litterale d un reseau prive/VPN (RFC1918, CGNAT/tailnet
     * 100.64/10, boucle locale). Seul cas ou http:// est accepte : le trafic y est
     * deja chiffre par le tunnel (WireGuard/VPN) ou reste sur la machine.
     */
    static boolean isPrivateHost(String host) {
        if (host == null) return false;
        if (host.equals("localhost")) return true;
        String[] q = host.split("\\.");
        if (q.length != 4) return false;
        int a, b;
        try { a = Integer.parseInt(q[0]); b = Integer.parseInt(q[1]); }
        catch (NumberFormatException e) { return false; }
        if (a == 10 || a == 127) return true;
        if (a == 192 && b == 168) return true;
        if (a == 172 && b >= 16 && b <= 31) return true;
        if (a == 100 && b >= 64 && b <= 127) return true;   // CGNAT / tailnet
        if (a == 169 && b == 254) return true;
        return false;
    }
}