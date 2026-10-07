package com.ridi.paperlauncher;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.DialogInterface;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextPaint;
import android.text.TextUtils;
import android.text.format.DateFormat;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.text.Collator;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;
import java.util.List;

/** Single opaque HOME view: fixed shelf, app grid and clock. */
public final class PaperHomeActivity extends Activity {
    private static final int BAR_APPEARANCE = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
    private ShelfView shelf;
    private final BroadcastReceiver changes = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (Intent.ACTION_PACKAGE_ADDED.equals(action)
                    || Intent.ACTION_PACKAGE_REMOVED.equals(action)
                    || Intent.ACTION_PACKAGE_CHANGED.equals(action)) {
                shelf.loadApps();
            } else {
                shelf.invalidate();
            }
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        getWindow().setStatusBarColor(Color.WHITE);
        getWindow().setNavigationBarColor(Color.WHITE);
        getWindow().getDecorView().setSystemUiVisibility(BAR_APPEARANCE);
        shelf = new ShelfView(this);
        setContentView(shelf);
        shelf.loadApps();
        IntentFilter packages = new IntentFilter();
        packages.addAction(Intent.ACTION_PACKAGE_ADDED);
        packages.addAction(Intent.ACTION_PACKAGE_REMOVED);
        packages.addAction(Intent.ACTION_PACKAGE_CHANGED);
        packages.addDataScheme("package");
        registerReceiver(changes, packages);
        IntentFilter clock = new IntentFilter();
        clock.addAction(Intent.ACTION_TIME_TICK);
        clock.addAction(Intent.ACTION_TIME_CHANGED);
        clock.addAction(Intent.ACTION_TIMEZONE_CHANGED);
        clock.addAction(Intent.ACTION_LOCALE_CHANGED);
        registerReceiver(changes, clock);
    }

    @Override protected void onResume() {
        super.onResume();
        getWindow().getDecorView().setSystemUiVisibility(BAR_APPEARANCE);
        shelf.invalidate();
    }

    @Override protected void onPause() {
        shelf.cancelPendingLongPress();
        // Keep a chosen move source across transient pauses (for example, a
        // dialog or system panel). Back explicitly cancels the selection.
        super.onPause();
    }

    @Override public void onBackPressed() {
        if (shelf.cancelMove()) return;
        super.onBackPressed();
    }

    @Override protected void onDestroy() {
        unregisterReceiver(changes);
        super.onDestroy();
    }

    private static final class App {
        final CharSequence label;
        final Drawable icon;
        final ComponentName component;
        App(CharSequence label, Drawable icon, ComponentName component) {
            this.label = label;
            this.icon = icon;
            this.component = component;
        }
    }

    private final class ShelfView extends View {
        private static final float IMAGE_WIDTH = 1086f;
        private static final float IMAGE_HEIGHT = 1448f;
        private static final int PAGE_SIZE = 10;
        // Coordinates are in the 1086 x 1448 shelf image.
        private static final int ICON_SIZE = 140;
        private static final float ICON_BOTTOM_FROM_SHELF = 50f;
        private static final float CLOCK_SCALE = 0.87f;
        private static final float CLOCK_CENTER_Y = 337.5f;
        private static final float CLOCK_CARD_WIDTH = 196f * CLOCK_SCALE;
        private static final float CLOCK_CARD_HEIGHT = 294f * CLOCK_SCALE;
        private static final float CLOCK_CARD_TOP = CLOCK_CENTER_Y - CLOCK_CARD_HEIGHT / 2f;
        private static final float CLOCK_PAIR_GAP = 16f * CLOCK_SCALE;
        private static final float CLOCK_MIDDLE_GAP = 88f * CLOCK_SCALE;
        private final float[] centersX = {141f, 341f, 541f, 739f, 939f};
        private final float[] shelfY = {825f, 1076f};
        private final Paint imagePaint = new Paint(Paint.FILTER_BITMAP_FLAG);
        private final TextPaint textPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        private final Paint clockPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint movePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Bitmap background;
        private final Bitmap flapBack;
        private final Bitmap flapFront;
        private final ArrayList<App> apps = new ArrayList<>();
        private final ArrayList<App> hiddenApps = new ArrayList<>();
        private int page;
        private float downX, downY;
        private Runnable longPress;
        private boolean longPressed;
        private App movingApp;

        ShelfView(Context context) {
            super(context);
            setBackgroundColor(Color.WHITE);
            background = BitmapFactory.decodeResource(getResources(), R.drawable.shelf);
            BitmapFactory.Options flapOptions = new BitmapFactory.Options();
            flapOptions.inSampleSize = 2;
            flapBack = BitmapFactory.decodeResource(getResources(), R.drawable.flap_back,
                    flapOptions);
            flapFront = BitmapFactory.decodeResource(getResources(), R.drawable.flap_front,
                    flapOptions);
            textPaint.setColor(0xFF777777);
            textPaint.setTextSize(23f);
            textPaint.setTextAlign(Paint.Align.CENTER);
            textPaint.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            clockPaint.setColor(Color.BLACK);
            clockPaint.setTextSize(308f * CLOCK_SCALE);
            clockPaint.setTextAlign(Paint.Align.CENTER);
            clockPaint.setTypeface(Typeface.createFromAsset(getAssets(), "RozhaOne.ttf"));
            movePaint.setColor(Color.BLACK);
            movePaint.setStyle(Paint.Style.STROKE);
            movePaint.setStrokeWidth(3f);
        }

        void loadApps() {
            PackageManager pm = getPackageManager();
            Intent query = new Intent(Intent.ACTION_MAIN);
            query.addCategory(Intent.CATEGORY_LAUNCHER);
            List<ResolveInfo> found = pm.queryIntentActivities(query, 0);
            ArrayList<App> updated = new ArrayList<>(found.size());
            ArrayList<App> hidden = new ArrayList<>();
            Set<String> hiddenNames = getPreferences(MODE_PRIVATE)
                    .getStringSet("hidden_apps", Collections.<String>emptySet());
            for (ResolveInfo info : found) {
                if (info.activityInfo == null
                        || getPackageName().equals(info.activityInfo.packageName)) continue;
                App app = new App(info.loadLabel(pm), info.loadIcon(pm),
                        new ComponentName(info.activityInfo.packageName, info.activityInfo.name));
                (hiddenNames.contains(app.component.flattenToString()) ? hidden : updated).add(app);
            }
            final Collator collator = Collator.getInstance();
            Comparator<App> byName = new Comparator<App>() {
                @Override public int compare(App a, App b) {
                    int result = collator.compare(a.label.toString(), b.label.toString());
                    return result != 0 ? result : a.component.flattenToString()
                            .compareTo(b.component.flattenToString());
                }
            };
            Collections.sort(updated, byName);
            Collections.sort(hidden, byName);
            ComponentName selected = movingApp == null ? null : movingApp.component;
            apps.clear();
            restoreOrder(updated);
            movingApp = null;
            if (selected != null) {
                for (App app : apps) {
                    if (app != null && selected.equals(app.component)) {
                        movingApp = app;
                        break;
                    }
                }
            }
            hiddenApps.clear();
            hiddenApps.addAll(hidden);
            page = Math.min(page, maxPage());
            invalidate();
        }

        private void restoreOrder(ArrayList<App> visible) {
            HashMap<String, App> byComponent = new HashMap<>();
            for (App app : visible) {
                byComponent.put(app.component.flattenToString(), app);
            }
            Set<String> placed = new HashSet<>();
            try {
                JSONArray order = new JSONArray(getPreferences(MODE_PRIVATE)
                        .getString("app_order", "[]"));
                for (int i = 0; i < order.length() && i < 500; i++) {
                    String key = order.isNull(i) ? null : order.optString(i, null);
                    App app = key == null ? null : byComponent.get(key);
                    if (app != null && !placed.add(key)) app = null;
                    apps.add(app);
                }
            } catch (JSONException ignored) {
                apps.clear();
            }
            while (!apps.isEmpty() && apps.get(apps.size() - 1) == null) {
                apps.remove(apps.size() - 1);
            }
            for (App app : visible) {
                if (!placed.contains(app.component.flattenToString())) apps.add(app);
            }
        }

        private void saveOrder() {
            JSONArray order = new JSONArray();
            for (App app : apps) {
                order.put(app == null ? JSONObject.NULL : app.component.flattenToString());
            }
            // Reordering is infrequent; commit before returning so a quick
            // suspend or power-off cannot lose the new shelf arrangement.
            getPreferences(MODE_PRIVATE).edit().putString("app_order", order.toString()).commit();
        }

        private boolean cancelMove() {
            if (movingApp == null) return false;
            movingApp = null;
            invalidate();
            return true;
        }

        int maxPage() {
            return Math.max(0, (apps.size() - 1) / PAGE_SIZE);
        }

        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            int save = canvas.save();
            canvas.scale(getWidth() / IMAGE_WIDTH, getHeight() / IMAGE_HEIGHT);
            if (background != null) {
                canvas.drawBitmap(background, null,
                        new RectF(0, 0, IMAGE_WIDTH, IMAGE_HEIGHT), imagePaint);
            } else {
                canvas.drawColor(Color.WHITE);
            }
            drawFlapClock(canvas);
            for (int slot = 0; slot < PAGE_SIZE; slot++) {
                int index = page * PAGE_SIZE + slot;
                if (index >= apps.size()) break;
                App app = apps.get(index);
                if (app == null) continue;
                float x = centersX[slot % 5];
                float y = shelfY[slot / 5];
                drawAppIcon(canvas, app, x, y);
                CharSequence label = TextUtils.ellipsize(app.label, textPaint, 176f,
                        TextUtils.TruncateAt.END);
                canvas.drawText(label.toString(), x, y - 9f, textPaint);
            }
            if (movingApp != null) {
                textPaint.setTextSize(21f);
                canvas.drawText("옮길 위치를 누르세요 · 뒤로: 취소", IMAGE_WIDTH / 2f,
                        1380f, textPaint);
                textPaint.setTextSize(23f);
            }
            if (maxPage() > 0) {
                textPaint.setTextSize(21f);
                canvas.drawText((page + 1) + " / " + (maxPage() + 1),
                        IMAGE_WIDTH / 2f, 1410f, textPaint);
                textPaint.setTextSize(23f);
            }
            canvas.restoreToCount(save);
        }

        private void drawFlapClock(Canvas canvas) {
            String digits = DateFormat.format("HHmm", new Date()).toString();
            float clockWidth = 4f * CLOCK_CARD_WIDTH + 2f * CLOCK_PAIR_GAP
                    + CLOCK_MIDDLE_GAP;
            float left = (IMAGE_WIDTH - clockWidth) / 2f;
            Rect digitBounds = new Rect();
            clockPaint.getTextBounds("8", 0, 1, digitBounds);
            float baseline = CLOCK_CARD_TOP + CLOCK_CARD_HEIGHT / 2f
                    - (digitBounds.top + digitBounds.bottom) / 2f;
            for (int i = 0; i < 4; i++) {
                float x = left + i * (CLOCK_CARD_WIDTH + CLOCK_PAIR_GAP);
                if (i >= 2) x += CLOCK_MIDDLE_GAP - CLOCK_PAIR_GAP;
                RectF card = new RectF(x, CLOCK_CARD_TOP, x + CLOCK_CARD_WIDTH,
                        CLOCK_CARD_TOP + CLOCK_CARD_HEIGHT);
                canvas.drawBitmap(flapBack, null, card, imagePaint);
                canvas.drawText(digits.substring(i, i + 1), card.centerX(), baseline,
                        clockPaint);
                // The transparent front image adds the hinge over the digit's center.
                canvas.drawBitmap(flapFront, null, card, imagePaint);
            }
            float colonX = IMAGE_WIDTH / 2f;
            float centerY = CLOCK_CARD_TOP + CLOCK_CARD_HEIGHT / 2f;
            canvas.drawCircle(colonX, centerY - 36f * CLOCK_SCALE, 9f * CLOCK_SCALE, clockPaint);
            canvas.drawCircle(colonX, centerY + 36f * CLOCK_SCALE, 9f * CLOCK_SCALE, clockPaint);
        }

        private void drawAppIcon(Canvas canvas, App app, float x, float shelfTop) {
            final float scaleX = getWidth() / IMAGE_WIDTH;
            final float scaleY = getHeight() / IMAGE_HEIGHT;
            final float iconScale = Math.min(scaleX, scaleY);
            final int save = canvas.save();
            canvas.translate(x, shelfTop - ICON_BOTTOM_FROM_SHELF);
            // The shelf image fills the available area, but icons must stay square
            // when status/navigation bars change the available height.
            canvas.scale(iconScale / scaleX, iconScale / scaleY);
            final int naturalWidth = Math.max(1, app.icon.getIntrinsicWidth());
            final int naturalHeight = Math.max(1, app.icon.getIntrinsicHeight());
            final float fit = ICON_SIZE / (float) Math.max(naturalWidth, naturalHeight);
            final int width = Math.max(1, Math.round(naturalWidth * fit));
            final int height = Math.max(1, Math.round(naturalHeight * fit));
            final int left = -width / 2;
            app.icon.setBounds(left, -height, left + width, 0);
            app.icon.draw(canvas);
            if (app == movingApp) {
                canvas.drawRect(left - 5f, -height - 5f, left + width + 5f, 5f, movePaint);
            }
            canvas.restoreToCount(save);
        }

        private int slotAt(float x, float y) {
            for (int row = 0; row < 2; row++) {
                if (y < shelfY[row] - ICON_BOTTOM_FROM_SHELF - ICON_SIZE - 10f
                        || y > shelfY[row] + 4f) continue;
                for (int col = 0; col < 5; col++) {
                    if (Math.abs(x - centersX[col]) > 96f) continue;
                    return page * PAGE_SIZE + row * 5 + col;
                }
            }
            return -1;
        }

        private int appAt(float x, float y) {
            int index = slotAt(x, y);
            return index >= 0 && index < apps.size() && apps.get(index) != null ? index : -1;
        }

        private void moveAppTo(int target) {
            int source = apps.indexOf(movingApp);
            if (source < 0 || target < 0) {
                cancelMove();
                return;
            }
            while (apps.size() <= target) apps.add(null);
            App displaced = apps.get(target);
            apps.set(target, movingApp);
            apps.set(source, displaced);
            while (!apps.isEmpty() && apps.get(apps.size() - 1) == null) {
                apps.remove(apps.size() - 1);
            }
            movingApp = null;
            page = Math.min(page, maxPage());
            saveOrder();
            invalidate();
        }

        private void cancelPendingLongPress() {
            if (longPress != null) {
                removeCallbacks(longPress);
                longPress = null;
            }
        }

        @Override protected void onDetachedFromWindow() {
            cancelPendingLongPress();
            super.onDetachedFromWindow();
        }

        @Override public boolean onTouchEvent(MotionEvent event) {
            float x = event.getX() * IMAGE_WIDTH / getWidth();
            float y = event.getY() * IMAGE_HEIGHT / getHeight();
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = x;
                    downY = y;
                    longPressed = false;
                    int index = appAt(x, y);
                    final App pressedApp = index >= 0 ? apps.get(index) : null;
                    if (movingApp == null && (pressedApp != null || !hiddenApps.isEmpty())) {
                        longPress = new Runnable() {
                            @Override public void run() {
                                longPress = null;
                                longPressed = true;
                                if (pressedApp != null) showAppMenu(pressedApp);
                                else showRestoreMenu();
                            }
                        };
                        postDelayed(longPress, ViewConfiguration.getLongPressTimeout());
                    }
                    return true;
                case MotionEvent.ACTION_MOVE:
                    if (Math.abs(x - downX) > 22f || Math.abs(y - downY) > 22f) {
                        cancelPendingLongPress();
                    }
                    return true;
                case MotionEvent.ACTION_POINTER_DOWN:
                case MotionEvent.ACTION_CANCEL:
                    cancelPendingLongPress();
                    return true;
                case MotionEvent.ACTION_UP:
                    cancelPendingLongPress();
                    if (longPressed) return true;
                    float dx = x - downX;
                    float dy = y - downY;
                    if (Math.abs(dx) > 70f && Math.abs(dx) > Math.abs(dy)) {
                        int next = Math.max(0, Math.min(maxPage(), page + (dx < 0 ? 1 : -1)));
                        if (next != page) {
                            page = next;
                            invalidate(); // Entire page changes immediately, with no animator.
                        }
                        return true;
                    }
                    if (movingApp != null) {
                        // Accept a tap when it begins and ends in the same slot;
                        // E Ink touch coordinates can jitter by more than 30px.
                        int target = slotAt(downX, downY);
                        if (target >= 0 && target == slotAt(x, y)) {
                            moveAppTo(target);
                        }
                    } else if (Math.abs(dx) < 30f && Math.abs(dy) < 30f) {
                        int tapped = appAt(downX, downY);
                        if (tapped >= 0) openApp(apps.get(tapped));
                    }
                    return true;
                default:
                    return true;
            }
        }

        private void showAppMenu(final App app) {
            AlertDialog dialog = new AlertDialog.Builder(PaperHomeActivity.this)
                    .setTitle(app.label)
                    .setItems(new String[]{"위치 변경", "홈에서 제거", "앱 삭제…"},
                            new DialogInterface.OnClickListener() {
                                @Override public void onClick(DialogInterface whichDialog, int which) {
                                    if (which == 0) {
                                        movingApp = app;
                                        invalidate();
                                    } else if (which == 1) {
                                        Set<String> names = new HashSet<>(getPreferences(MODE_PRIVATE)
                                                .getStringSet("hidden_apps",
                                                        Collections.<String>emptySet()));
                                        names.add(app.component.flattenToString());
                                        getPreferences(MODE_PRIVATE).edit()
                                                .putStringSet("hidden_apps", names).apply();
                                        loadApps();
                                    } else {
                                        Intent uninstall = new Intent(Intent.ACTION_DELETE,
                                                Uri.parse("package:" + app.component.getPackageName()));
                                        try {
                                            startActivity(uninstall);
                                        } catch (ActivityNotFoundException ignored) {
                                            // No package installer on this image.
                                        }
                                    }
                                }
                            }).create();
            dialog.getWindow().setWindowAnimations(0);
            dialog.show();
        }

        private void showRestoreMenu() {
            if (hiddenApps.isEmpty()) return;
            final ArrayList<App> choices = new ArrayList<>(hiddenApps);
            String[] labels = new String[choices.size()];
            for (int i = 0; i < choices.size(); i++) {
                labels[i] = choices.get(i).label.toString();
            }
            AlertDialog dialog = new AlertDialog.Builder(PaperHomeActivity.this)
                    .setTitle("숨긴 앱 다시 표시")
                    .setItems(labels, new DialogInterface.OnClickListener() {
                        @Override public void onClick(DialogInterface whichDialog, int which) {
                            Set<String> names = new HashSet<>(getPreferences(MODE_PRIVATE)
                                    .getStringSet("hidden_apps", Collections.<String>emptySet()));
                            names.remove(choices.get(which).component.flattenToString());
                            getPreferences(MODE_PRIVATE).edit()
                                    .putStringSet("hidden_apps", names).apply();
                            loadApps();
                        }
                    }).create();
            dialog.getWindow().setWindowAnimations(0);
            dialog.show();
        }

        private void openApp(App app) {
            Intent launch = new Intent(Intent.ACTION_MAIN);
            launch.addCategory(Intent.CATEGORY_LAUNCHER);
            launch.setComponent(app.component);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            try {
                startActivity(launch);
            } catch (ActivityNotFoundException | SecurityException ignored) {
                loadApps();
            }
        }
    }
}
