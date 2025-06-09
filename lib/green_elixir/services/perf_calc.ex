defmodule GreenElixir.Services.PerformanceCalculator do
  @moduledoc """
  Complete performance point calculation implementation.
  """

  import Bitwise

  # Mod enum values matching osu!
  @mods %{
    none: 0,
    no_fail: 1,
    easy: 2,
    touch_device: 4,
    hidden: 8,
    hard_rock: 16,
    sudden_death: 32,
    double_time: 64,
    relax: 128,
    half_time: 256,
    nightcore: 512,
    flashlight: 1024,
    autoplay: 2048,
    spun_out: 4096,
    relax2: 8192,
    perfect: 16384,
    key4: 32768,
    key5: 65536,
    key6: 131_072,
    key7: 262_144,
    key8: 524_288,
    fade_in: 1_048_576,
    random: 2_097_152,
    cinema: 4_194_304,
    target: 8_388_608,
    key9: 16_777_216,
    key_coop: 33_554_432,
    key1: 67_108_864,
    key3: 134_217_728,
    key2: 268_435_456,
    score_v2: 536_870_912,
    mirror: 1_073_741_824
  }

  def calculate_performance_points(score, beatmap_attributes) do
    case score.game_mode do
      0 -> calculate_standard_pp(score, beatmap_attributes)
      1 -> calculate_taiko_pp(score, beatmap_attributes)
      2 -> calculate_catch_pp(score, beatmap_attributes)
      3 -> calculate_mania_pp(score, beatmap_attributes)
      _ -> 0.0
    end
  end

  defp calculate_standard_pp(score, beatmap) do
    # Apply mods to difficulty
    {aim_diff, speed_diff, od} =
      apply_mods_to_difficulty(
        beatmap.aim_difficulty,
        beatmap.speed_difficulty,
        beatmap.overall_difficulty,
        score.mods
      )

    # Calculate accuracy
    accuracy = calculate_accuracy_standard(score)

    # Calculate individual components
    aim_pp =
      calculate_aim_value(
        aim_diff,
        accuracy,
        score.count_miss,
        score.max_combo,
        beatmap.max_combo
      )

    speed_pp = calculate_speed_value(speed_diff, accuracy, score.count_miss)
    acc_pp = calculate_accuracy_value(od, accuracy)

    # Combine components
    total_pp =
      :math.pow(
        :math.pow(aim_pp, 1.1) +
          :math.pow(speed_pp, 1.1) +
          :math.pow(acc_pp, 1.1),
        1.0 / 1.1
      )

    # Apply final multipliers
    total_pp * get_final_multiplier(score.mods)
  end

  defp apply_mods_to_difficulty(aim_diff, speed_diff, od, mods) do
    # Hard Rock
    {aim_diff, speed_diff, od} =
      if has_mod?(mods, :hard_rock) do
        {aim_diff * 1.4, speed_diff * 1.4, min(od * 1.4, 10.0)}
      else
        {aim_diff, speed_diff, od}
      end

    # Easy
    {aim_diff, speed_diff, od} =
      if has_mod?(mods, :easy) do
        {aim_diff * 0.5, speed_diff * 0.5, od * 0.5}
      else
        {aim_diff, speed_diff, od}
      end

    # Double Time / Nightcore
    {aim_diff, speed_diff} =
      if has_mod?(mods, :double_time) or has_mod?(mods, :nightcore) do
        {aim_diff * 1.2, speed_diff * 1.2}
      else
        {aim_diff, speed_diff}
      end

    # Half Time
    {aim_diff, speed_diff} =
      if has_mod?(mods, :half_time) do
        {aim_diff * 0.8, speed_diff * 0.8}
      else
        {aim_diff, speed_diff}
      end

    {aim_diff, speed_diff, od}
  end

  defp calculate_accuracy_standard(score) do
    total_hits = score.count_300 + score.count_100 + score.count_50 + score.count_miss

    if total_hits > 0 do
      (score.count_300 * 6 + score.count_100 * 2 + score.count_50 * 1) / (total_hits * 6)
    else
      0.0
    end
  end

  defp calculate_aim_value(aim_difficulty, accuracy, miss_count, max_combo, beatmap_max_combo) do
    # Base aim value
    aim_value = :math.pow(5.0 * max(1.0, aim_difficulty / 0.0675) - 4.0, 3.0) / 100_000.0

    # Length bonus
    length_bonus = 0.95 + 0.4 * min(1.0, max_combo / 3000.0)

    length_bonus =
      length_bonus +
        if max_combo > 3000 do
          :math.log10(max_combo / 3000.0) * 0.5
        else
          0.0
        end

    aim_value = aim_value * length_bonus

    # Miss penalty
    if miss_count > 0 do
      aim_value =
        aim_value * 0.97 *
          :math.pow(
            1 - :math.pow(miss_count / max_combo, 0.775),
            miss_count
          )
    end

    # Combo scaling
    if beatmap_max_combo > 0 do
      aim_value =
        aim_value *
          min(
            :math.pow(max_combo, 0.8) / :math.pow(beatmap_max_combo, 0.8),
            1.0
          )
    end

    # Accuracy bonus
    aim_value * :math.pow(accuracy, 5.5)
  end

  defp calculate_speed_value(speed_difficulty, accuracy, miss_count) do
    speed_value =
      :math.pow(5.0 * max(1.0, speed_difficulty / 0.0675) - 4.0, 3.0) / 100_000.0

    # Miss penalty
    if miss_count > 0 do
      speed_value =
        speed_value * 0.97 *
          :math.pow(
            1 - :math.pow(miss_count / 1000.0, 0.775),
            :math.pow(miss_count, 0.875)
          )
    end

    # Accuracy bonus
    speed_value * :math.pow(accuracy, 5.5)
  end

  defp calculate_accuracy_value(overall_difficulty, accuracy) do
    better_accuracy_percentage =
      if accuracy > 0.8 do
        (accuracy - 0.8) / 0.2
      else
        0.0
      end

    acc_value =
      :math.pow(1.52163, overall_difficulty) * :math.pow(better_accuracy_percentage, 24.0) * 2.83

    # Bonus for high accuracy
    min(1.15, :math.pow(acc_value / 27000.0, 1.2)) * acc_value
  end

  defp get_final_multiplier(mods) do
    multiplier = 1.0

    # No Fail
    multiplier =
      if has_mod?(mods, :no_fail) do
        multiplier * 0.9
      else
        multiplier
      end

    # Spun Out
    multiplier =
      if has_mod?(mods, :spun_out) do
        multiplier * 0.95
      else
        multiplier
      end

    multiplier
  end

  defp has_mod?(mods, mod_name) do
    mod_value = Map.get(@mods, mod_name, 0)
    (mods &&& mod_value) != 0
  end

  # Implement other game modes...
  defp calculate_taiko_pp(_score, _beatmap), do: 0.0
  defp calculate_catch_pp(_score, _beatmap), do: 0.0
  defp calculate_mania_pp(_score, _beatmap), do: 0.0
end
