/*
 * DEEP DRIFT - a tiny original underwater survival game for PS Vita
 *
 * You are a diver whose boat sank. Dive down, grab 10 pieces of scrap
 * to build a raft, and come back up for air before your oxygen runs out!
 *
 * Controls:
 *   Left stick / D-pad  = swim
 *   START               = restart after win / game over
 *   SELECT              = quit
 *
 * Built with VitaSDK + vita2d.
 */

#include <psp2/ctrl.h>
#include <psp2/kernel/processmgr.h>
#include <vita2d.h>
#include <stdlib.h>
#include <math.h>

/* ---------- Settings you can tweak! ---------- */
#define SCREEN_W      960
#define SCREEN_H      544
#define SURFACE_Y     70      /* where the water starts */
#define PLAYER_SPEED  4.0f
#define PLAYER_SIZE   14
#define MAX_OXYGEN    100.0f
#define MAX_HEALTH    100.0f
#define SCRAP_TO_WIN  10
#define NUM_SCRAP     4       /* scrap pieces on screen at once */
#define NUM_FISH      5       /* dangerous fish */

/* ---------- Things in the game ---------- */
typedef struct {
    float x, y;
} Scrap;

typedef struct {
    float x, y;
    float speed;   /* negative = swimming left */
} Fish;

/* Game state (all in one place so restarting is easy) */
float player_x, player_y;
float oxygen, health;
int   scrap_count;
int   hurt_timer;      /* frames of "can't get hurt" after a hit */
int   state;           /* 0 = playing, 1 = won, 2 = game over */
Scrap scraps[NUM_SCRAP];
Fish  fish[NUM_FISH];

/* Random number between lo and hi */
float rand_range(float lo, float hi) {
    return lo + (hi - lo) * (rand() / (float)RAND_MAX);
}

void place_scrap(Scrap *s) {
    s->x = rand_range(30, SCREEN_W - 30);
    s->y = rand_range(SURFACE_Y + 120, SCREEN_H - 30);  /* always deep-ish */
}

void place_fish(Fish *f) {
    f->y = rand_range(SURFACE_Y + 60, SCREEN_H - 20);
    f->speed = rand_range(1.5f, 3.5f);
    if (rand() % 2) {          /* start from the left side... */
        f->x = -40;
    } else {                   /* ...or from the right side */
        f->x = SCREEN_W + 40;
        f->speed = -f->speed;
    }
}

void reset_game(void) {
    player_x = SCREEN_W / 2;
    player_y = SURFACE_Y;
    oxygen = MAX_OXYGEN;
    health = MAX_HEALTH;
    scrap_count = 0;
    hurt_timer = 0;
    state = 0;
    for (int i = 0; i < NUM_SCRAP; i++) place_scrap(&scraps[i]);
    for (int i = 0; i < NUM_FISH; i++) {
        place_fish(&fish[i]);
        fish[i].x = rand_range(0, SCREEN_W);  /* spread them out at start */
    }
}

/* Are two circles touching? */
int touching(float x1, float y1, float r1, float x2, float y2, float r2) {
    float dx = x1 - x2, dy = y1 - y2;
    return dx * dx + dy * dy < (r1 + r2) * (r1 + r2);
}

void update(SceCtrlData *pad) {
    /* --- Move the player --- */
    float mx = 0, my = 0;

    /* Analog stick goes 0..255, middle is ~128. Ignore small wiggles. */
    float sx = (pad->lx - 128) / 128.0f;
    float sy = (pad->ly - 128) / 128.0f;
    if (fabsf(sx) > 0.25f) mx = sx;
    if (fabsf(sy) > 0.25f) my = sy;

    if (pad->buttons & SCE_CTRL_LEFT)  mx = -1;
    if (pad->buttons & SCE_CTRL_RIGHT) mx =  1;
    if (pad->buttons & SCE_CTRL_UP)    my = -1;
    if (pad->buttons & SCE_CTRL_DOWN)  my =  1;

    player_x += mx * PLAYER_SPEED;
    player_y += my * PLAYER_SPEED;

    /* Keep the player on screen and not flying above the water */
    if (player_x < PLAYER_SIZE) player_x = PLAYER_SIZE;
    if (player_x > SCREEN_W - PLAYER_SIZE) player_x = SCREEN_W - PLAYER_SIZE;
    if (player_y < SURFACE_Y) player_y = SURFACE_Y;
    if (player_y > SCREEN_H - PLAYER_SIZE) player_y = SCREEN_H - PLAYER_SIZE;

    /* --- Oxygen --- */
    if (player_y <= SURFACE_Y + 2) {
        oxygen += 1.0f;                       /* breathing at the top */
    } else {
        float depth = (player_y - SURFACE_Y) / (SCREEN_H - SURFACE_Y);
        oxygen -= 0.08f + depth * 0.12f;      /* deeper = uses air faster */
    }
    if (oxygen > MAX_OXYGEN) oxygen = MAX_OXYGEN;
    if (oxygen < 0) {
        oxygen = 0;
        health -= 0.4f;                       /* drowning! */
    }

    /* --- Scrap pickup --- */
    for (int i = 0; i < NUM_SCRAP; i++) {
        if (touching(player_x, player_y, PLAYER_SIZE, scraps[i].x, scraps[i].y, 10)) {
            scrap_count++;
            place_scrap(&scraps[i]);
        }
    }

    /* --- Fish --- */
    if (hurt_timer > 0) hurt_timer--;
    for (int i = 0; i < NUM_FISH; i++) {
        fish[i].x += fish[i].speed;
        if (fish[i].x < -60 || fish[i].x > SCREEN_W + 60) place_fish(&fish[i]);

        if (hurt_timer == 0 &&
            touching(player_x, player_y, PLAYER_SIZE, fish[i].x, fish[i].y, 16)) {
            health -= 20;
            hurt_timer = 60;                  /* 1 second of safety */
        }
    }

    /* --- Win / lose --- */
    if (scrap_count >= SCRAP_TO_WIN) state = 1;
    if (health <= 0) { health = 0; state = 2; }
}

/* Draw a bar like the oxygen or health meter */
void draw_bar(vita2d_pgf *font, int x, int y, const char *label, float value, float max, unsigned int color) {
    vita2d_pgf_draw_text(font, x, y + 16, RGBA8(255, 255, 255, 255), 1.0f, label);
    vita2d_draw_rectangle(x + 90, y, 200, 20, RGBA8(40, 40, 40, 255));
    vita2d_draw_rectangle(x + 90, y, 200 * (value / max), 20, color);
}

void draw(vita2d_pgf *font) {
    /* Sky */
    vita2d_draw_rectangle(0, 0, SCREEN_W, SURFACE_Y, RGBA8(135, 200, 250, 255));

    /* Water: draw stripes that get darker the deeper they are */
    int bands = 12;
    int band_h = (SCREEN_H - SURFACE_Y) / bands + 1;
    for (int i = 0; i < bands; i++) {
        int dark = i * 14;
        vita2d_draw_rectangle(0, SURFACE_Y + i * band_h, SCREEN_W, band_h,
                              RGBA8(20, 140 - dark / 2, 200 - dark, 255));
    }

    /* Scrap = yellow squares */
    for (int i = 0; i < NUM_SCRAP; i++) {
        vita2d_draw_rectangle(scraps[i].x - 8, scraps[i].y - 8, 16, 16, RGBA8(240, 200, 40, 255));
    }

    /* Fish = red circles with a tail */
    for (int i = 0; i < NUM_FISH; i++) {
        float tail = fish[i].speed > 0 ? -22 : 22;
        vita2d_draw_fill_circle(fish[i].x + tail, fish[i].y, 8, RGBA8(160, 30, 30, 255));
        vita2d_draw_fill_circle(fish[i].x, fish[i].y, 16, RGBA8(220, 50, 50, 255));
    }

    /* Player = orange diver (blinks after getting hurt) */
    if (hurt_timer % 10 < 5) {
        vita2d_draw_fill_circle(player_x, player_y, PLAYER_SIZE, RGBA8(255, 140, 0, 255));
        vita2d_draw_fill_circle(player_x + 5, player_y - 3, 5, RGBA8(200, 240, 255, 255)); /* mask */
    }

    /* HUD */
    draw_bar(font, 10, 10, "Oxygen", oxygen, MAX_OXYGEN, RGBA8(80, 200, 255, 255));
    draw_bar(font, 10, 38, "Health", health, MAX_HEALTH, RGBA8(80, 220, 80, 255));
    vita2d_pgf_draw_textf(font, 700, 30, RGBA8(0, 0, 0, 255), 1.2f,
                          "Scrap: %d / %d", scrap_count, SCRAP_TO_WIN);

    if (state == 1) {
        vita2d_pgf_draw_text(font, 250, 270, RGBA8(255, 255, 255, 255), 2.0f, "You built a raft! You win!");
        vita2d_pgf_draw_text(font, 340, 320, RGBA8(255, 255, 255, 255), 1.2f, "Press START to play again");
    } else if (state == 2) {
        vita2d_pgf_draw_text(font, 360, 270, RGBA8(255, 80, 80, 255), 2.0f, "GAME OVER");
        vita2d_pgf_draw_text(font, 340, 320, RGBA8(255, 255, 255, 255), 1.2f, "Press START to try again");
    }
}

int main(void) {
    vita2d_init();
    vita2d_set_clear_color(RGBA8(0, 0, 0, 255));
    vita2d_pgf *font = vita2d_load_default_pgf();

    sceCtrlSetSamplingMode(SCE_CTRL_MODE_ANALOG);
    SceCtrlData pad;

    srand(sceKernelGetProcessTimeLow());
    reset_game();

    while (1) {
        sceCtrlPeekBufferPositive(0, &pad, 1);
        if (pad.buttons & SCE_CTRL_SELECT) break;

        if (state == 0) {
            update(&pad);
        } else if (pad.buttons & SCE_CTRL_START) {
            reset_game();
        }

        vita2d_start_drawing();
        vita2d_clear_screen();
        draw(font);
        vita2d_end_drawing();
        vita2d_swap_buffers();   /* waits for the screen, so the game runs at 60fps */
    }

    vita2d_fini();
    vita2d_free_pgf(font);
    sceKernelExitProcess(0);
    return 0;
}
