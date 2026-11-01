// Procedural Nature Sound Effects & Ambient Audio Catalog (2026-10-31)
// Maps the 100 procedural WAV audio files in /assets/audio/ across 5 categories:
// 1. 01_rain_and_storms (20 files: 11 loops, 9 one-shots)
// 2. 02_wind_and_foliage (20 files: 10 loops, 10 one-shots)
// 3. 03_water_and_ocean (20 files: 10 loops, 10 one-shots)
// 4. 04_campfire_and_crackles (20 files: 6 loops, 14 one-shots)
// 5. 05_night_insects_and_birds (20 files: 5 loops, 15 one-shots)

const BASE = '/assets/audio';

export interface AmbientTrack {
  id: string;
  category: string;
  url: string;
  loop: boolean;
  duration: number;
}

export const AMBIENT_FILES: Record<string, { cat: string; loop: boolean; dur: number }> = {
  // 01_rain_and_storms
  rain_01_light_spring_drizzle_loop: { cat: '01_rain_and_storms', loop: true, dur: 18.0 },
  rain_02_steady_garden_rain_loop: { cat: '01_rain_and_storms', loop: true, dur: 22.0 },
  rain_03_heavy_downpour_loop: { cat: '01_rain_and_storms', loop: true, dur: 24.0 },
  rain_04_tropical_monsoon_loop: { cat: '01_rain_and_storms', loop: true, dur: 25.0 },
  rain_05_rain_on_forest_canopy_loop: { cat: '01_rain_and_storms', loop: true, dur: 20.0 },
  rain_06_rain_on_canvas_tent_loop: { cat: '01_rain_and_storms', loop: true, dur: 18.0 },
  rain_07_rain_on_wooden_cabin_roof_loop: { cat: '01_rain_and_storms', loop: true, dur: 20.0 },
  rain_08_rain_on_windowpane_loop: { cat: '01_rain_and_storms', loop: true, dur: 16.0 },
  rain_09_thunderstorm_ambience_loop: { cat: '01_rain_and_storms', loop: true, dur: 28.0 },
  rain_10_hail_shower_loop: { cat: '01_rain_and_storms', loop: true, dur: 15.0 },
  rain_11_post_storm_canopy_drips_loop: { cat: '01_rain_and_storms', loop: true, dur: 16.0 },
  rain_12_distant_rolling_thunder_01: { cat: '01_rain_and_storms', loop: false, dur: 8.5 },
  rain_13_distant_rolling_thunder_02: { cat: '01_rain_and_storms', loop: false, dur: 10.0 },
  rain_14_distant_rolling_thunder_03: { cat: '01_rain_and_storms', loop: false, dur: 7.0 },
  rain_15_close_thunderclap_strike_01: { cat: '01_rain_and_storms', loop: false, dur: 5.5 },
  rain_16_close_thunderclap_strike_02: { cat: '01_rain_and_storms', loop: false, dur: 6.5 },
  rain_17_close_thunderclap_strike_03: { cat: '01_rain_and_storms', loop: false, dur: 4.5 },
  rain_18_puddle_rain_gust_burst: { cat: '01_rain_and_storms', loop: false, dur: 6.0 },
  rain_19_single_puddle_splash_heavy: { cat: '01_rain_and_storms', loop: false, dur: 2.0 },
  rain_20_eaves_water_runoff_trickle: { cat: '01_rain_and_storms', loop: false, dur: 9.0 },

  // 02_wind_and_foliage
  wind_01_gentle_meadow_breeze_loop: { cat: '02_wind_and_foliage', loop: true, dur: 20.0 },
  wind_02_steady_forest_wind_loop: { cat: '02_wind_and_foliage', loop: true, dur: 22.0 },
  wind_03_howling_canyon_wind_loop: { cat: '02_wind_and_foliage', loop: true, dur: 24.0 },
  wind_04_winter_blizzard_gale_loop: { cat: '02_wind_and_foliage', loop: true, dur: 25.0 },
  wind_05_desert_sand_wind_loop: { cat: '02_wind_and_foliage', loop: true, dur: 18.0 },
  wind_06_mountain_summit_draft_loop: { cat: '02_wind_and_foliage', loop: true, dur: 20.0 },
  wind_07_whistling_pine_needles_loop: { cat: '02_wind_and_foliage', loop: true, dur: 18.0 },
  wind_08_broadleaf_canopy_rustle_loop: { cat: '02_wind_and_foliage', loop: true, dur: 20.0 },
  wind_09_tall_grass_prairie_sway_loop: { cat: '02_wind_and_foliage', loop: true, dur: 16.0 },
  wind_10_bamboo_grove_wind_loop: { cat: '02_wind_and_foliage', loop: true, dur: 18.0 },
  wind_11_short_wind_gust_soft: { cat: '02_wind_and_foliage', loop: false, dur: 3.5 },
  wind_12_short_wind_gust_strong: { cat: '02_wind_and_foliage', loop: false, dur: 4.5 },
  wind_13_whistling_wind_whip: { cat: '02_wind_and_foliage', loop: false, dur: 3.0 },
  wind_14_dry_autumn_leaves_scatter: { cat: '02_wind_and_foliage', loop: false, dur: 4.0 },
  wind_15_bush_foliage_rustle_short_01: { cat: '02_wind_and_foliage', loop: false, dur: 1.8 },
  wind_16_bush_foliage_rustle_short_02: { cat: '02_wind_and_foliage', loop: false, dur: 2.2 },
  wind_17_bush_foliage_shake_heavy: { cat: '02_wind_and_foliage', loop: false, dur: 3.0 },
  wind_18_tall_grass_footstep_swish: { cat: '02_wind_and_foliage', loop: false, dur: 1.5 },
  wind_19_creaking_tree_trunk_01: { cat: '02_wind_and_foliage', loop: false, dur: 4.0 },
  wind_20_creaking_tree_branch_02: { cat: '02_wind_and_foliage', loop: false, dur: 3.2 },

  // 03_water_and_ocean
  water_01_babbling_brook_loop: { cat: '03_water_and_ocean', loop: true, dur: 20.0 },
  water_02_fast_mountain_stream_loop: { cat: '03_water_and_ocean', loop: true, dur: 20.0 },
  water_03_wide_rushing_river_loop: { cat: '03_water_and_ocean', loop: true, dur: 22.0 },
  water_04_distant_waterfall_roar_loop: { cat: '03_water_and_ocean', loop: true, dur: 24.0 },
  water_05_close_waterfall_cascade_loop: { cat: '03_water_and_ocean', loop: true, dur: 22.0 },
  water_06_calm_sandy_beach_waves_loop: { cat: '03_water_and_ocean', loop: true, dur: 26.0 },
  water_07_crashing_rocky_shore_surf_loop: { cat: '03_water_and_ocean', loop: true, dur: 28.0 },
  water_08_gentle_lake_lapping_loop: { cat: '03_water_and_ocean', loop: true, dur: 18.0 },
  water_09_cavern_echo_water_drips_loop: { cat: '03_water_and_ocean', loop: true, dur: 20.0 },
  water_10_underwater_submerged_ambience_loop: { cat: '03_water_and_ocean', loop: true, dur: 18.0 },
  water_11_single_ocean_wave_wash_soft: { cat: '03_water_and_ocean', loop: false, dur: 6.5 },
  water_12_single_ocean_wave_crash_big: { cat: '03_water_and_ocean', loop: false, dur: 8.0 },
  water_13_shore_wave_pebble_drawback: { cat: '03_water_and_ocean', loop: false, dur: 5.5 },
  water_14_water_splash_small_stone: { cat: '03_water_and_ocean', loop: false, dur: 1.8 },
  water_15_water_splash_medium_jump: { cat: '03_water_and_ocean', loop: false, dur: 2.5 },
  water_16_water_splash_large_plunge: { cat: '03_water_and_ocean', loop: false, dur: 3.5 },
  water_17_water_wading_slosh: { cat: '03_water_and_ocean', loop: false, dur: 2.2 },
  water_18_cave_water_drip_single_01: { cat: '03_water_and_ocean', loop: false, dur: 1.5 },
  water_19_cave_water_drip_single_02: { cat: '03_water_and_ocean', loop: false, dur: 1.5 },
  water_20_cave_water_drip_cluster: { cat: '03_water_and_ocean', loop: false, dur: 3.0 },

  // 04_campfire_and_crackles
  fire_01_cozy_campfire_steady_loop: { cat: '04_campfire_and_crackles', loop: true, dur: 20.0 },
  fire_02_roaring_bonfire_loop: { cat: '04_campfire_and_crackles', loop: true, dur: 22.0 },
  fire_03_dying_embers_hiss_loop: { cat: '04_campfire_and_crackles', loop: true, dur: 18.0 },
  fire_04_hearth_fireplace_rumble_loop: { cat: '04_campfire_and_crackles', loop: true, dur: 20.0 },
  fire_05_torch_flame_flutter_loop: { cat: '04_campfire_and_crackles', loop: true, dur: 15.0 },
  fire_06_brushfire_crackle_wall_loop: { cat: '04_campfire_and_crackles', loop: true, dur: 20.0 },
  fire_07_sharp_pine_wood_snap_01: { cat: '04_campfire_and_crackles', loop: false, dur: 1.5 },
  fire_08_sharp_pine_wood_snap_02: { cat: '04_campfire_and_crackles', loop: false, dur: 1.8 },
  fire_09_sharp_pine_wood_snap_03: { cat: '04_campfire_and_crackles', loop: false, dur: 1.5 },
  fire_10_deep_log_split_crack_04: { cat: '04_campfire_and_crackles', loop: false, dur: 2.2 },
  fire_11_rapid_spark_crackle_burst_01: { cat: '04_campfire_and_crackles', loop: false, dur: 3.5 },
  fire_12_rapid_spark_crackle_burst_02: { cat: '04_campfire_and_crackles', loop: false, dur: 4.0 },
  fire_13_rapid_spark_crackle_burst_03: { cat: '04_campfire_and_crackles', loop: false, dur: 3.0 },
  fire_14_sap_sizzle_hiss_01: { cat: '04_campfire_and_crackles', loop: false, dur: 3.2 },
  fire_15_sap_sizzle_hiss_02: { cat: '04_campfire_and_crackles', loop: false, dur: 2.8 },
  fire_16_wet_drop_on_hot_coals: { cat: '04_campfire_and_crackles', loop: false, dur: 2.0 },
  fire_17_flame_flare_whoosh_01: { cat: '04_campfire_and_crackles', loop: false, dur: 2.5 },
  fire_18_flame_flare_whoosh_02: { cat: '04_campfire_and_crackles', loop: false, dur: 3.0 },
  fire_19_torch_swing_whoosh_03: { cat: '04_campfire_and_crackles', loop: false, dur: 1.6 },
  fire_20_shifting_charred_logs_crumble: { cat: '04_campfire_and_crackles', loop: false, dur: 4.5 },

  // 05_night_insects_and_birds
  wildlife_01_summer_night_cricket_chorus_loop: { cat: '05_night_insects_and_birds', loop: true, dur: 20.0 },
  wildlife_02_swamp_crickets_and_katydids_loop: { cat: '05_night_insects_and_birds', loop: true, dur: 22.0 },
  wildlife_03_midday_cicada_drone_loop: { cat: '05_night_insects_and_birds', loop: true, dur: 20.0 },
  wildlife_04_dawn_forest_bird_chorus_loop: { cat: '05_night_insects_and_birds', loop: true, dur: 24.0 },
  wildlife_05_night_pond_frogs_and_crickets_loop: { cat: '05_night_insects_and_birds', loop: true, dur: 22.0 },
  wildlife_06_single_cricket_chirp_01: { cat: '05_night_insects_and_birds', loop: false, dur: 1.8 },
  wildlife_07_single_cricket_chirp_02: { cat: '05_night_insects_and_birds', loop: false, dur: 2.2 },
  wildlife_08_katydid_rasp_call: { cat: '05_night_insects_and_birds', loop: false, dur: 2.0 },
  wildlife_09_cicada_windup_call_01: { cat: '05_night_insects_and_birds', loop: false, dur: 5.5 },
  wildlife_10_cicada_short_buzz_02: { cat: '05_night_insects_and_birds', loop: false, dur: 3.0 },
  wildlife_11_songbird_melodic_tweet_01: { cat: '05_night_insects_and_birds', loop: false, dur: 2.2 },
  wildlife_12_songbird_warble_trill_02: { cat: '05_night_insects_and_birds', loop: false, dur: 2.8 },
  wildlife_13_songbird_canyon_whistle_03: { cat: '05_night_insects_and_birds', loop: false, dur: 2.5 },
  wildlife_14_songbird_sparrow_chirps_04: { cat: '05_night_insects_and_birds', loop: false, dur: 2.0 },
  wildlife_15_great_horned_owl_hoot_01: { cat: '05_night_insects_and_birds', loop: false, dur: 4.0 },
  wildlife_16_barred_owl_call_02: { cat: '05_night_insects_and_birds', loop: false, dur: 4.5 },
  wildlife_17_bullfrog_deep_croak_01: { cat: '05_night_insects_and_birds', loop: false, dur: 2.0 },
  wildlife_18_tree_frog_double_ribbit_02: { cat: '05_night_insects_and_birds', loop: false, dur: 1.8 },
  wildlife_19_woodpecker_tree_drilling_01: { cat: '05_night_insects_and_birds', loop: false, dur: 2.5 },
  wildlife_20_woodpecker_slow_tapping_02: { cat: '05_night_insects_and_birds', loop: false, dur: 3.0 },
};

// Aliases mapping simplified names to catalog ids
export const AMBIENT_ALIASES: Record<string, string> = {
  // Water loops & effects
  water_beach: 'water_06_calm_sandy_beach_waves_loop',
  water_surf: 'water_07_crashing_rocky_shore_surf_loop',
  water_lake: 'water_08_gentle_lake_lapping_loop',
  water_river: 'water_03_wide_rushing_river_loop',
  water_brook: 'water_01_babbling_brook_loop',
  water_stream: 'water_02_fast_mountain_stream_loop',
  water_submerged: 'water_10_underwater_submerged_ambience_loop',
  water_cavern: 'water_09_cavern_echo_water_drips_loop',
  water_wading: 'water_17_water_wading_slosh',
  water_splash_stone: 'water_14_water_splash_small_stone',
  water_splash_medium: 'water_15_water_splash_medium_jump',
  water_splash_plunge: 'water_16_water_splash_large_plunge',

  // Campfire & crackles
  fire_campfire: 'fire_01_cozy_campfire_steady_loop',
  fire_bonfire: 'fire_02_roaring_bonfire_loop',
  fire_embers: 'fire_03_dying_embers_hiss_loop',
  fire_hearth: 'fire_04_hearth_fireplace_rumble_loop',
  fire_torch: 'fire_05_torch_flame_flutter_loop',
  fire_brushfire: 'fire_06_brushfire_crackle_wall_loop',

  // Wind & foliage
  wind_meadow: 'wind_01_gentle_meadow_breeze_loop',
  wind_forest: 'wind_02_steady_forest_wind_loop',
  wind_canyon: 'wind_03_howling_canyon_wind_loop',
  wind_blizzard: 'wind_04_winter_blizzard_gale_loop',
  wind_desert: 'wind_05_desert_sand_wind_loop',
  wind_summit: 'wind_06_mountain_summit_draft_loop',
  wind_pines: 'wind_07_whistling_pine_needles_loop',
  wind_prairie: 'wind_09_tall_grass_prairie_sway_loop',

  // Diurnal wildlife
  wildlife_night_crickets: 'wildlife_01_summer_night_cricket_chorus_loop',
  wildlife_swamp: 'wildlife_02_swamp_crickets_and_katydids_loop',
  wildlife_cicadas_noon: 'wildlife_03_midday_cicada_drone_loop',
  wildlife_dawn_birds: 'wildlife_04_dawn_forest_bird_chorus_loop',
  wildlife_night_pond: 'wildlife_05_night_pond_frogs_and_crickets_loop',

  // Rain & storms
  rain_drizzle: 'rain_01_light_spring_drizzle_loop',
  rain_steady: 'rain_02_steady_garden_rain_loop',
  rain_heavy: 'rain_03_heavy_downpour_loop',
  rain_monsoon: 'rain_04_tropical_monsoon_loop',
  rain_canopy: 'rain_05_rain_on_forest_canopy_loop',
  rain_tent: 'rain_06_rain_on_canvas_tent_loop',
  rain_cabin: 'rain_07_rain_on_wooden_cabin_roof_loop',
  rain_window: 'rain_08_rain_on_windowpane_loop',
  rain_thunderstorm: 'rain_09_thunderstorm_ambience_loop',
  rain_hail: 'rain_10_hail_shower_loop',
  rain_post_storm: 'rain_11_post_storm_canopy_drips_loop',
  rain_eaves: 'rain_20_eaves_water_runoff_trickle',
  rain_puddle_gust: 'rain_18_puddle_rain_gust_burst',
  rain_puddle_splash: 'rain_19_single_puddle_splash_heavy',

  // Foliage sweeteners
  foliage_bush: 'wind_15_bush_foliage_rustle_short_01',
  foliage_bush_heavy: 'wind_17_bush_foliage_shake_heavy',
  foliage_grass_step: 'wind_18_tall_grass_footstep_swish',
  foliage_leaves: 'wind_14_dry_autumn_leaves_scatter',
  foliage_tree_creak: 'wind_19_creaking_tree_trunk_01',
  foliage_branch_creak: 'wind_20_creaking_tree_branch_02',

  // Fire sweeteners
  fire_snap: 'fire_07_sharp_pine_wood_snap_01',
  fire_burst: 'fire_11_rapid_spark_crackle_burst_01',
  fire_sizzle: 'fire_14_sap_sizzle_hiss_01',
  fire_coals_wet: 'fire_16_wet_drop_on_hot_coals',
  fire_flare: 'fire_17_flame_flare_whoosh_01',
  fire_crumble: 'fire_20_shifting_charred_logs_crumble',

  // Wildlife sweeteners
  bird_song: 'wildlife_11_songbird_melodic_tweet_01',
  bird_trill: 'wildlife_12_songbird_warble_trill_02',
  bird_whistle: 'wildlife_13_songbird_canyon_whistle_03',
  bird_sparrow: 'wildlife_14_songbird_sparrow_chirps_04',
  bird_owl: 'wildlife_15_great_horned_owl_hoot_01',
  bird_woodpecker: 'wildlife_19_woodpecker_tree_drilling_01',
  wildlife_frog: 'wildlife_17_bullfrog_deep_croak_01',
  wildlife_katydid: 'wildlife_08_katydid_rasp_call',
  wildlife_cicada: 'wildlife_09_cicada_windup_call_01',
};

// Procedural sound pools for randomized variety
export const AMBIENT_POOLS: Record<string, string[]> = {
  // Water
  water_frog: ['wildlife_17_bullfrog_deep_croak_01', 'wildlife_18_tree_frog_double_ribbit_02'],
  water_wave_wash: ['water_11_single_ocean_wave_wash_soft', 'water_12_single_ocean_wave_crash_big', 'water_13_shore_wave_pebble_drawback'],
  water_drip: ['water_18_cave_water_drip_single_01', 'water_19_cave_water_drip_single_02', 'water_20_cave_water_drip_cluster'],

  // Fire
  fire_snap: ['fire_07_sharp_pine_wood_snap_01', 'fire_08_sharp_pine_wood_snap_02', 'fire_09_sharp_pine_wood_snap_03', 'fire_10_deep_log_split_crack_04'],
  fire_burst: ['fire_11_rapid_spark_crackle_burst_01', 'fire_12_rapid_spark_crackle_burst_02', 'fire_13_rapid_spark_crackle_burst_03'],
  fire_sizzle: ['fire_14_sap_sizzle_hiss_01', 'fire_15_sap_sizzle_hiss_02'],
  fire_flare: ['fire_17_flame_flare_whoosh_01', 'fire_18_flame_flare_whoosh_02'],

  // Wind & Foliage
  wind_gust: ['wind_11_short_wind_gust_soft', 'wind_12_short_wind_gust_strong', 'wind_13_whistling_wind_whip'],
  foliage_rustle: ['wind_15_bush_foliage_rustle_short_01', 'wind_16_bush_foliage_rustle_short_02'],
  tree_creak: ['wind_19_creaking_tree_trunk_01', 'wind_20_creaking_tree_branch_02'],

  // Birds & Wildlife
  bird_song: ['wildlife_11_songbird_melodic_tweet_01', 'wildlife_12_songbird_warble_trill_02', 'wildlife_13_songbird_canyon_whistle_03', 'wildlife_14_songbird_sparrow_chirps_04'],
  woodpecker: ['wildlife_19_woodpecker_tree_drilling_01', 'wildlife_20_woodpecker_slow_tapping_02'],
  owl: ['wildlife_15_great_horned_owl_hoot_01', 'wildlife_16_barred_owl_call_02'],
  night_cricket: ['wildlife_06_single_cricket_chirp_01', 'wildlife_07_single_cricket_chirp_02', 'wildlife_08_katydid_rasp_call'],
  cicada: ['wildlife_09_cicada_windup_call_01', 'wildlife_10_cicada_short_buzz_02'],

  // Storm & Thunder
  thunder_distant: ['rain_12_distant_rolling_thunder_01', 'rain_13_distant_rolling_thunder_02', 'rain_14_distant_rolling_thunder_03'],
  thunder_strike: ['rain_15_close_thunderclap_strike_01', 'rain_16_close_thunderclap_strike_02', 'rain_17_close_thunderclap_strike_03'],
};

/** Resolves an ambient sound ID or alias to its public URL (/assets/audio/...). */
export function getAmbientAudioUrl(name: string): string | null {
  const resolved = AMBIENT_ALIASES[name] ?? name;
  const meta = AMBIENT_FILES[resolved];
  if (meta) {
    return `${BASE}/${meta.cat}/${resolved}.wav`;
  }
  return null;
}
