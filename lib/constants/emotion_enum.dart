enum EmotionEnum {
  ANGER("anger"),
  DISGUST("disgust"),
  FEAR("fear"),
  HAPPINESS("happiness"),
  SADNESS("sadness"),
  SURPRISE("surprise"),
  NEUTRAL("neutral");

  const EmotionEnum(this.value);
  final String value;
}

//List<String> emotions = [EmotionEnum.ANGER.value, EmotionEnum.DISGUST.value, EmotionEnum.FEAR.value, EmotionEnum.HAPPINESS.value, EmotionEnum.SADNESS.value, EmotionEnum.NEUTRAL.value];
//private static String[] emotions={"","Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"};
