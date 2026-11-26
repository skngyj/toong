import 'dart:math';

/// 확률 비율로 정할 수 있는 칸 수(후보마다 1~10).
const drawWeightMin = 1;
const drawWeightMax = 10;

/// [weights] 비율대로 한 칸을 뽑아 그 위치를 돌려준다. 비율은 모두 1 이상이어야 한다.
int pickWeighted(List<int> weights, Random random) {
  final total = weights.fold(0, (sum, w) => sum + w);
  var x = random.nextInt(total);
  for (var i = 0; i < weights.length; i++) {
    if (x < weights[i]) return i;
    x -= weights[i];
  }
  return weights.length - 1;
}

/// 비율을 퍼센트(소수점 없이)로 바꾼다. 합이 100이 되도록 나머지는 큰 소수부터 1씩 나눈다.
List<int> weightPercents(List<int> weights) {
  final total = weights.fold(0, (sum, w) => sum + w);
  if (total == 0) return [for (final _ in weights) 0];
  final exact = [for (final w in weights) w * 100 / total];
  final result = [for (final e in exact) e.floor()];
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) => (exact[b] - result[b]).compareTo(exact[a] - result[a]));
  var left = 100 - result.fold(0, (sum, p) => sum + p);
  for (final i in order) {
    if (left == 0) break;
    result[i]++;
    left--;
  }
  return result;
}
