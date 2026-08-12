package org.safedesk.app;

import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

/** Choix du mode d affichage a l installation. Ecran deja concu "accessible". */
public class ProfileActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setBackgroundColor(Color.parseColor("#0F1115"));
        col.setPadding(dp(24), dp(40), dp(24), dp(24));
        col.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView t = new TextView(this);
        t.setText("Comment veux-tu l'affichage ?");
        t.setTextColor(Color.WHITE);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        t.setGravity(Gravity.CENTER);
        col.addView(t);

        TextView sub = new TextView(this);
        sub.setText("Tu pourras changer plus tard.");
        sub.setTextColor(Color.parseColor("#8B94A7"));
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, dp(8), 0, dp(28));
        col.addView(sub);

        // Ecran de tablette (>= 600dp) : la surface tactile est le choix naturel.
        boolean bigScreen = getResources().getConfiguration().smallestScreenWidthDp >= 600;

        if (bigScreen) {
            col.addView(card("\uD83D\uDC46  Tablette tactile", "Ton espace en plein ecran,\ntout se fait au doigt.",
                    "#14B8A6", "#0F1115", true, "standard", "tablet"));
            col.addView(card("\uD83D\uDC53  Confort", "Grands boutons, gros texte,\nune chose a la fois.",
                    "#1A1F29", "#E8ECF3", false, "senior", "phone"));
            col.addView(card("\u25A6  Standard", "Accueil a tuiles classique.",
                    "#1A1F29", "#E8ECF3", false, "standard", "phone"));
        } else {
            col.addView(card("\uD83D\uDC53  Confort", "Grands boutons, gros texte,\nune chose a la fois.",
                    "#14B8A6", "#0F1115", true, "senior", "phone"));
            col.addView(card("\u25A6  Standard", "Grille classique, plus compacte.",
                    "#1A1F29", "#E8ECF3", false, "standard", "phone"));
        }

        setContentView(col);
    }

    private LinearLayout card(String title, String desc, String bg, String fg,
                              boolean recommended, String profile, String form) {
        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setBackgroundColor(Color.parseColor(bg));
        c.setPadding(dp(24), dp(26), dp(24), dp(26));
        c.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(18);
        c.setLayoutParams(lp);

        TextView tt = new TextView(this);
        tt.setText(title + (recommended ? "   \u2605 conseille" : ""));
        tt.setTextColor(Color.parseColor(fg));
        tt.setTextSize(TypedValue.COMPLEX_UNIT_SP, recommended ? 28 : 24);
        tt.setGravity(Gravity.CENTER);
        c.addView(tt);

        TextView dd = new TextView(this);
        dd.setText(desc);
        dd.setTextColor(Color.parseColor(recommended ? "#0F1115" : "#8B94A7"));
        dd.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        dd.setGravity(Gravity.CENTER);
        dd.setPadding(0, dp(10), 0, 0);
        c.addView(dd);

        c.setOnClickListener(v -> {
            Config.setProfile(this, profile);
            Config.setForm(this, form);
            startActivity(new Intent(this,
                    "tablet".equals(form) ? DesktopActivity.class : HomeActivity.class));
            finish();
        });
        return c;
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }
}