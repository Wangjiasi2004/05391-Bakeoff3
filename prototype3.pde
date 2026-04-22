import java.io.BufferedReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Random;

// Set the DPI to make your smartwatch 1 inch square. Measure it on the screen.
final int DPIofYourDeviceScreen = 125;

// Do not change the following variables.
String[] phrases;
String[] suggestions;
int totalTrialNum = 3 + (int)random(3);
int currTrialNum = 0;
float startTime = 0;
float finishTime = 0;
float lastTime = 0;
float lettersEnteredTotal = 0;
float lettersExpectedTotal = 0;
float errorsTotal = 0;
String currentPhrase = "";
String currentTyped = "";
final float sizeOfInputArea = DPIofYourDeviceScreen * 1;
PImage watch;
PImage mouseCursor;
float cursorHeight;
float cursorWidth;

// Prototype 3: nine-key/T9 input. Each tap records a letter group.
// The current digit sequence is converted to the most likely word.
final String[] T9_DIGITS = {
  "2", "3", "4",
  "5", "6", "7",
  "8", "9"
};

final String[] T9_LABELS = {
  "ABC", "DEF", "GHI",
  "JKL", "MNO", "PQRS",
  "TUV", "WXYZ"
};

final String[] T9_LETTERS = {
  "abc", "def", "ghi",
  "jkl", "mno", "pqrs",
  "tuv", "wxyz"
};

final int ACTION_NONE = 0;
final int ACTION_DELETE = 1;
final int ACTION_SPACE = 2;
final int ACTION_PREDICT_BASE = 10;
final int ACTION_T9_BASE = 100;

final int CANDIDATE_SLOTS = 6;
final int PREDICTION_TILE_COUNT = 4;
final int BUCKET_CAPACITY = 18;
final int MAX_UNIGRAM_WORDS = 400000;
final int MAX_DICTIONARY_WORD_LENGTH = 14;
final int MAX_WORD_DIGITS = 14;
final int BEAM_WIDTH = 10;
final int SEGMENT_BEAM_WIDTH = 12;
final float CONTEXT_SCORE_MULTIPLIER = 2.35;
final float PAIR_CONTEXT_SCORE_MULTIPLIER = 2.80;
final float CONTEXT_PREFIX_SCORE_MULTIPLIER = 1.85;
final float PAIR_CONTEXT_PREFIX_SCORE_MULTIPLIER = 2.20;
final float UNIGRAM_SCORE_MULTIPLIER = 1.00;
final float PREFIX_SCORE_MULTIPLIER = 0.95;
final float PREFIX_EXTRA_LETTER_PENALTY = 0.16;
final float SINGLE_GROUP_PREFIX_MULTIPLIER = 1.18;
final float EXACT_WORD_SCORE_BONUS = 3.50;
final float SHORT_EXACT_WORD_BONUS = 4.25;
final float WORD_BREAK_PENALTY = 70.0;
final float WORD_LENGTH_BONUS = 1.45;
final float WHOLE_INPUT_WORD_BONUS = 10.0;
final float ONE_LETTER_WORD_BONUS = 10.0;
final long COUNT_BIG_MULTIPLIER = 1500L;
final long DICTIONARY_WORD_COUNT = 1200L;
final long STRONG_PREFIX_COUNT = 1000000L;

final float NEXT_BUTTON_X = 500;
final float NEXT_BUTTON_Y = 245;
final float NEXT_BUTTON_W = 280;
final float NEXT_BUTTON_H = 180;

HashMap<String, CandidateBucket> sequenceBuckets = new HashMap<String, CandidateBucket>();
HashMap<String, CandidateBucket> prefixSequenceBuckets = new HashMap<String, CandidateBucket>();
HashMap<String, CandidateBucket> contextSequenceBuckets = new HashMap<String, CandidateBucket>();
HashMap<String, CandidateBucket> contextPrefixSequenceBuckets = new HashMap<String, CandidateBucket>();
HashMap<String, CandidateBucket> nextWordBuckets = new HashMap<String, CandidateBucket>();
HashMap<String, Float> letterNgramScores = new HashMap<String, Float>();
HashMap<String, Long> sequencePrefixCounts = new HashMap<String, Long>();
HashMap<String, Boolean> dictionaryWords = new HashMap<String, Boolean>();
CandidateBucket fallbackPredictionBucket = new CandidateBucket();
String[] visibleCandidates = new String[CANDIDATE_SLOTS];

String committedTyped = "";
String t9Sequence = "";
String livePrediction = "";
int selectedCandidateIndex = 0;
int activeTapAction = ACTION_NONE;

void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());
  loadLanguageModel();
  clearVisibleCandidates();

  orientation(LANDSCAPE);
  size(800, 800);
  textFont(createFont("Arial", 24));
  noStroke();

  noCursor();
  mouseCursor = loadImage("finger.png");
  cursorHeight = DPIofYourDeviceScreen * (400.0 / 250.0);
  cursorWidth = cursorHeight * 0.6;
}

void draw()
{
  background(255);
  drawWatch();
  drawInputArea();

  if (finishTime != 0)
  {
    fill(128);
    textAlign(CENTER);
    text("Finished", 280, 150);
    cursor(ARROW);
    return;
  }

  if (startTime == 0 && !mousePressed)
  {
    fill(128);
    textAlign(CENTER);
    text("Click to start time!", 280, 150);
  }

  if (startTime == 0 && mousePressed)
    nextTrial();

  if (startTime != 0)
    drawOutsideUI();

  image(mouseCursor, mouseX + cursorWidth / 2 - cursorWidth / 3, mouseY + cursorHeight / 2 - cursorHeight / 5, cursorWidth, cursorHeight);
}

void drawInputArea()
{
  refreshT9Preview();

  fill(34);
  rect(inputLeft(), inputTop(), sizeOfInputArea, sizeOfInputArea, 18);
  fill(50);
  rect(inputLeft() + 4, inputTop() + 4, sizeOfInputArea - 8, sizeOfInputArea - 8, 15);

  drawHomeKeyboard();
}

void drawHomeKeyboard()
{
  int hoverAction = hoveredAction();
  textAlign(CENTER, CENTER);
  drawTopStrip(hoverAction);

  for (int row = 0; row < 3; row++)
  {
    for (int col = 0; col < 3; col++)
    {
      int action = keyboardActionAt(row, col);
      float x = keyboardCellLeft(col) + buttonInset();
      float y = keyboardCellTop(row) + buttonInset();
      float w = keyboardCellWidth() - buttonInset() * 2;
      float h = keyboardCellHeight() - buttonInset() * 2;
      boolean isPressed = action == activeTapAction;
      boolean isHighlighted = isPressed || hoverAction == action;

      fill(homeButtonColor(action, true, isHighlighted));
      rect(x, y, w, h, 10);

      if (action == ACTION_SPACE)
        drawSpaceKey(x, y, w, h, isHighlighted);
      else
        drawT9Key(action - ACTION_T9_BASE, x, y, w, h, isHighlighted);
    }
  }
}

void drawTopStrip(int hoverAction)
{
  float topY = inputTop() + buttonInset();
  float topH = topStripHeight() - buttonInset() * 2;
  float deleteX = inputLeft() + buttonInset();
  float deleteW = keyboardCellWidth() - buttonInset() * 2;
  boolean deletePressed = activeTapAction == ACTION_DELETE;
  boolean deleteHighlighted = deletePressed || hoverAction == ACTION_DELETE;

  fill(homeButtonColor(ACTION_DELETE, true, deleteHighlighted));
  rect(deleteX, topY, deleteW, topH, 10);
  fill(deleteHighlighted ? color(20) : color(248));
  textSize(13);
  text("del", deleteX + deleteW / 2, topY + topH / 2 + 1);

  for (int i = 0; i < PREDICTION_TILE_COUNT; i++)
  {
    int action = ACTION_PREDICT_BASE + i;
    float x = predictionTileLeft(i) + buttonInset();
    float y = predictionTileTop(i) + buttonInset();
    float w = predictionTileWidth() - buttonInset() * 2;
    float h = predictionTileHeight() - buttonInset() * 2;
    boolean enabled = predictionEnabled(i);
    boolean isPressed = activeTapAction == action;
    boolean isHighlighted = enabled && (isPressed || hoverAction == action);

    fill(homeButtonColor(action, enabled, isHighlighted));
    rect(x, y, w, h, 8);
    drawPredictionTile(i, x, y, w, h, enabled, isHighlighted);
  }
}

void drawPredictionTile(int index, float x, float y, float w, float h, boolean enabled, boolean isPressed)
{
  if (!enabled)
    return;

  String label = visibleCandidates[index];
  fill(isPressed ? color(20) : color(250));
  int labelSize = predictionTileLabelSize(label);
  textSize(labelSize);
  text(fitLabel(label, w - 5, labelSize), x + w / 2, y + h / 2 + 1);
}

void drawT9Key(int keyIndex, float x, float y, float w, float h, boolean isPressed)
{
  if (keyIndex < 0 || keyIndex >= T9_LABELS.length)
    return;

  fill(isPressed ? color(20) : color(248));
  textSize(T9_LABELS[keyIndex].length() == 4 ? 13 : 14);
  text(T9_LABELS[keyIndex], x + w / 2, y + h / 2 + 1);
}

void drawSpaceKey(float x, float y, float w, float h, boolean isPressed)
{
  fill(isPressed ? color(20) : color(248));
  textSize(12);
  text("space", x + w / 2, y + h / 2 + 1);
}

void drawOutsideUI()
{
  syncCurrentTyped();

  textAlign(LEFT, CENTER);
  fill(110);
  textSize(22);
  text("Phrase " + (currTrialNum + 1) + "/" + totalTrialNum, 70, 190);
  fill(45);
  drawFittedLeftText(currentPhrase, 70, 245, 410, 38, 18);
  fill(55);
  textSize(24);
  text("Entered:  " + currentTyped + "|", 70, 300);

  fill(255);
  rect(NEXT_BUTTON_X, NEXT_BUTTON_Y, NEXT_BUTTON_W, NEXT_BUTTON_H, 18);
  fill(100);
  textAlign(CENTER, CENTER);
  textSize(42);
  text("NEXT >", NEXT_BUTTON_X + NEXT_BUTTON_W / 2, NEXT_BUTTON_Y + NEXT_BUTTON_H / 2);
}

boolean didMouseClick(float x, float y, float w, float h)
{
  return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
}

void mousePressed()
{
  if (finishTime != 0)
    return;

  if (didMouseClick(NEXT_BUTTON_X, NEXT_BUTTON_Y, NEXT_BUTTON_W, NEXT_BUTTON_H))
  {
    nextTrial();
    return;
  }

  if (startTime == 0)
    return;

  if (!isInsideInput(mouseX, mouseY))
    return;

  int action = touchActionAt(mouseX, mouseY);
  if (action == ACTION_NONE)
    return;

  activeTapAction = action;
}

void mouseReleased()
{
  if (activeTapAction == ACTION_NONE)
    return;

  int releasedAction = touchActionAt(mouseX, mouseY);

  if (releasedAction == activeTapAction)
    handleTapAction(activeTapAction);

  activeTapAction = ACTION_NONE;
}

void handleTapAction(int action)
{
  if (action == ACTION_DELETE)
  {
    deleteOneStep();
    return;
  }

  if (action == ACTION_SPACE)
  {
    commitT9Word();
    return;
  }

  if (isPredictionAction(action))
  {
    applyPrediction(action - ACTION_PREDICT_BASE);
    return;
  }

  if (action >= ACTION_T9_BASE)
  {
    int keyIndex = action - ACTION_T9_BASE;
    if (keyIndex >= 0 && keyIndex < T9_DIGITS.length)
    {
      t9Sequence += T9_DIGITS[keyIndex];
      selectedCandidateIndex = 0;
    }
  }

  refreshT9Preview();
}

void deleteOneStep()
{
  if (t9Sequence.length() > 0)
  {
    t9Sequence = t9Sequence.substring(0, t9Sequence.length() - 1);
    selectedCandidateIndex = 0;
    refreshT9Preview();
    return;
  }

  if (committedTyped.length() > 0)
    committedTyped = committedTyped.substring(0, committedTyped.length() - 1);

  syncCurrentTyped();
}

void commitT9Word()
{
  refreshT9Preview();

  if (t9Sequence.length() > 0)
  {
    String word = livePrediction;
    if (word == null || word.length() == 0)
      word = fallbackWordFromSequence(t9Sequence);

    appendCommittedPrediction(word);
    t9Sequence = "";
    livePrediction = "";
    selectedCandidateIndex = 0;
    clearVisibleCandidates();
    syncCurrentTyped();
    return;
  }

  if (committedTyped.length() > 0 && committedTyped.charAt(committedTyped.length() - 1) == ' ' && predictionEnabled(0))
  {
    appendCommittedPrediction(visibleCandidates[0]);
    clearVisibleCandidates();
    syncCurrentTyped();
    return;
  }

  if (committedTyped.length() > 0 && committedTyped.charAt(committedTyped.length() - 1) != ' ')
    committedTyped += " ";

  syncCurrentTyped();
}

void applyPrediction(int index)
{
  refreshT9Preview();

  if (!predictionEnabled(index))
    return;

  String prediction = visibleCandidates[index];
  if (prediction == null || prediction.length() == 0)
    return;

  appendCommittedPrediction(prediction);
  t9Sequence = "";
  livePrediction = "";
  selectedCandidateIndex = 0;
  clearVisibleCandidates();
  syncCurrentTyped();
}

void appendCommittedPrediction(String prediction)
{
  String cleaned = prediction.trim();
  if (cleaned.length() == 0)
    return;

  if (committedTyped.length() > 0 && committedTyped.charAt(committedTyped.length() - 1) != ' ')
    committedTyped += " ";

  committedTyped += cleaned;
  if (committedTyped.charAt(committedTyped.length() - 1) != ' ')
    committedTyped += " ";
}

void refreshT9Preview()
{
  clearVisibleCandidates();

  if (t9Sequence.length() == 0)
  {
    fillNextWordPredictions();
    livePrediction = "";
    selectedCandidateIndex = 0;
    syncCurrentTyped();
    return;
  }

  String[] candidates = bestCandidatesForSequence(t9Sequence, previousCommittedWord());
  fillCurrentTypingPredictions(candidates);

  int count = visibleCandidateCount();
  if (selectedCandidateIndex >= count)
    selectedCandidateIndex = 0;

  livePrediction = visibleCandidates[selectedCandidateIndex];
  if (livePrediction == null || livePrediction.length() == 0)
    livePrediction = fallbackWordFromSequence(t9Sequence);

  syncCurrentTyped();
}

String[] bestPredictionsForSequence(String sequence, String previousWord)
{
  String[] segmented = bestSegmentationsForSequence(sequence, previousWord);
  if (shouldStayInsideCurrentWord(sequence, segmented[0]))
    return bestCandidatesForSequence(sequence, previousWord);

  if (segmented[0] != null && segmented[0].length() > 0)
    return segmented;

  return bestCandidatesForSequence(sequence, previousWord);
}

boolean shouldStayInsideCurrentWord(String sequence, String segmentedText)
{
  if (segmentedText == null || segmentedText.indexOf(' ') < 0)
    return false;
  if (sequenceBuckets.get(sequence) != null)
    return false;

  Long prefixCount = sequencePrefixCounts.get(sequence);
  if (prefixCount == null)
    return false;

  return prefixCount.longValue() >= STRONG_PREFIX_COUNT || sequence.length() <= 4;
}

String[] bestSegmentationsForSequence(String sequence, String previousWord)
{
  String[] result = new String[CANDIDATE_SLOTS];
  int n = sequence.length();
  ArrayList[] paths = new ArrayList[n + 1];
  paths[0] = new ArrayList<SegPath>();
  paths[0].add(new SegPath("", previousWord, 0, 0));

  for (int start = 0; start < n; start++)
  {
    if (paths[start] == null)
      continue;

    int maxLen = min(MAX_WORD_DIGITS, n - start);
    for (int len = 1; len <= maxLen; len++)
    {
      int end = start + len;
      String segment = sequence.substring(start, end);
      CandidateBucket bucket = sequenceBuckets.get(segment);
      if (bucket == null)
        continue;

      for (int pathIndex = 0; pathIndex < paths[start].size(); pathIndex++)
      {
        SegPath path = (SegPath)paths[start].get(pathIndex);
        for (int wordIndex = 0; wordIndex < bucket.words.length; wordIndex++)
        {
          String word = bucket.words[wordIndex];
          if (word == null)
            continue;

          float score = path.score + scoreSegmentWord(word, segment, bucket.counts[wordIndex], path.lastWord, path.wordCount > 0, start == 0 && end == n);
          String text = path.text.length() == 0 ? word : path.text + " " + word;
          addSegPath(paths, end, new SegPath(text, word, score, path.wordCount + 1), SEGMENT_BEAM_WIDTH);
        }
      }
    }
  }

  if (paths[n] == null)
    return emptyPredictionList();

  for (int i = 0; i < min(CANDIDATE_SLOTS, paths[n].size()); i++)
    result[i] = ((SegPath)paths[n].get(i)).text;

  for (int i = 0; i < result.length; i++)
  {
    if (result[i] == null)
      result[i] = "";
  }
  return result;
}

float scoreSegmentWord(String word, String sequence, long count, String previousWord, boolean startsNewWord, boolean consumesWholeInput)
{
  float score = logScore(count) * UNIGRAM_SCORE_MULTIPLIER;
  score += min(word.length(), MAX_WORD_DIGITS) * WORD_LENGTH_BONUS;
  if (word.equals("a") || word.equals("i"))
    score += ONE_LETTER_WORD_BONUS;

  if (previousWord != null && previousWord.length() > 0)
  {
    CandidateBucket contextBucket = contextSequenceBuckets.get(contextKey(previousWord, sequence));
    if (contextBucket != null)
    {
      long contextCount = contextBucket.countFor(word);
      if (contextCount > 0)
        score += logScore(contextCount) * CONTEXT_SCORE_MULTIPLIER;
    }
  }

  if (startsNewWord)
    score -= WORD_BREAK_PENALTY;

  if (consumesWholeInput)
    score += WHOLE_INPUT_WORD_BONUS;

  return score;
}

void addSegPath(ArrayList[] paths, int index, SegPath candidate, int limit)
{
  if (paths[index] == null)
    paths[index] = new ArrayList<SegPath>();

  ArrayList list = paths[index];
  for (int i = 0; i < list.size(); i++)
  {
    SegPath existing = (SegPath)list.get(i);
    if (existing.text.equals(candidate.text))
    {
      if (candidate.score > existing.score)
      {
        list.set(i, candidate);
        sortSegPaths(list);
      }
      return;
    }
  }

  list.add(candidate);
  sortSegPaths(list);
  while (list.size() > limit)
    list.remove(list.size() - 1);
}

void sortSegPaths(ArrayList list)
{
  for (int i = 0; i < list.size(); i++)
  {
    for (int j = i + 1; j < list.size(); j++)
    {
      SegPath a = (SegPath)list.get(i);
      SegPath b = (SegPath)list.get(j);
      if (b.score > a.score)
      {
        list.set(i, b);
        list.set(j, a);
      }
    }
  }
}

String[] emptyPredictionList()
{
  String[] result = new String[CANDIDATE_SLOTS];
  for (int i = 0; i < result.length; i++)
    result[i] = "";
  return result;
}

String[] bestCandidatesForSequence(String sequence, String previousWord)
{
  String[] result = new String[CANDIDATE_SLOTS];
  float[] scores = new float[CANDIDATE_SLOTS];
  for (int i = 0; i < scores.length; i++)
    scores[i] = -1;

  HashMap<String, Float> scoreMap = new HashMap<String, Float>();
  if (previousWord.length() > 0)
    addBucketScores(scoreMap, contextSequenceBuckets.get(contextKey(previousWord, sequence)), CONTEXT_SCORE_MULTIPLIER, false);
  addBucketScores(scoreMap, sequenceBuckets.get(sequence), UNIGRAM_SCORE_MULTIPLIER, true);
  if (previousWord.length() > 0)
    addPrefixBucketScores(scoreMap, contextPrefixSequenceBuckets.get(contextKey(previousWord, sequence)), CONTEXT_PREFIX_SCORE_MULTIPLIER, sequence);
  addPrefixBucketScores(scoreMap, prefixSequenceBuckets.get(sequence), prefixScoreMultiplier(sequence), sequence);

  for (String word : scoreMap.keySet())
    insertScoredCandidate(result, scores, word, scoreMap.get(word));

  if (result[0] == null)
  {
    CandidateBucket bucket = sequenceBuckets.get(sequence);
    if (bucket != null)
    {
      for (int i = 0; i < bucket.words.length; i++)
      {
        if (bucket.words[i] != null)
          insertScoredCandidate(result, scores, bucket.words[i], logScore(bucket.counts[i]));
      }
    }
  }

  fillRemainingPrefixCandidates(result, prefixSequenceBuckets.get(sequence), sequence);

  for (int i = 0; i < result.length; i++)
  {
    if (result[i] == null)
      result[i] = "";
  }
  return result;
}

void fillNextWordPredictions()
{
  String previousWord = previousCommittedWord();
  if (previousWord.length() > 0)
    fillCandidatesFromBucket(nextWordBuckets.get(previousWord));

  fillCandidatesFromBucket(fallbackPredictionBucket);
}

void fillCurrentTypingPredictions(String[] candidates)
{
  if (candidates == null || candidates.length == 0)
    return;

  for (int i = 0; i < candidates.length; i++)
    addVisibleCandidate(candidates[i]);
}

void fillCandidatesFromBucket(CandidateBucket bucket)
{
  if (bucket == null)
    return;

  for (int i = 0; i < bucket.words.length; i++)
  {
    if (bucket.words[i] != null && bucket.words[i].length() > 0)
      addVisibleCandidate(bucket.words[i]);
  }
}

void addVisibleCandidate(String candidate)
{
  if (candidate == null || candidate.length() == 0)
    return;

  for (int i = 0; i < visibleCandidates.length; i++)
  {
    if (candidate.equals(visibleCandidates[i]))
      return;
  }

  for (int i = 0; i < visibleCandidates.length; i++)
  {
    if (visibleCandidates[i] == null || visibleCandidates[i].length() == 0)
    {
      visibleCandidates[i] = candidate;
      return;
    }
  }
}

String lastWordOf(String text)
{
  if (text == null)
    return "";

  String cleaned = text.trim().toLowerCase();
  if (cleaned.length() == 0)
    return "";

  int end = cleaned.length() - 1;
  while (end >= 0 && cleaned.charAt(end) == ' ')
    end--;
  if (end < 0)
    return "";

  int start = end;
  while (start >= 0 && cleaned.charAt(start) != ' ')
    start--;

  return cleaned.substring(start + 1, end + 1);
}

void addBucketScores(HashMap<String, Float> scoreMap, CandidateBucket bucket, float multiplier, boolean addExactBonus)
{
  if (bucket == null)
    return;

  for (int i = 0; i < bucket.words.length; i++)
  {
    String word = bucket.words[i];
    if (word == null || word.length() == 0)
      continue;

    float score = logScore(bucket.counts[i]) * multiplier;
    if (addExactBonus)
      score += exactCandidateBonus(word);
    Float current = scoreMap.get(word);
    if (current == null)
      scoreMap.put(word, score);
    else
      scoreMap.put(word, current + score);
  }
}

void addPrefixBucketScores(HashMap<String, Float> scoreMap, CandidateBucket bucket, float multiplier, String typedSequence)
{
  if (bucket == null)
    return;

  for (int i = 0; i < bucket.words.length; i++)
  {
    String word = bucket.words[i];
    if (word == null || word.length() == 0)
      continue;

    float extraLetters = max(0, word.length() - typedSequence.length());
    float score = logScore(bucket.counts[i]) * multiplier - extraLetters * PREFIX_EXTRA_LETTER_PENALTY;
    Float current = scoreMap.get(word);
    if (current == null)
      scoreMap.put(word, score);
    else
      scoreMap.put(word, current + score);
  }
}

float exactCandidateBonus(String word)
{
  if (word != null && word.length() <= 3)
    return SHORT_EXACT_WORD_BONUS;
  return EXACT_WORD_SCORE_BONUS;
}

void fillRemainingPrefixCandidates(String[] result, CandidateBucket bucket, String typedSequence)
{
  if (bucket == null)
    return;

  String[] prefixWords = new String[CANDIDATE_SLOTS];
  float[] prefixScores = new float[CANDIDATE_SLOTS];
  for (int i = 0; i < prefixScores.length; i++)
    prefixScores[i] = -1;

  for (int i = 0; i < bucket.words.length; i++)
  {
    String word = bucket.words[i];
    if (word == null || word.length() == 0)
      continue;
    if (candidateAlreadyPresent(result, word))
      continue;

    float extraLetters = max(0, word.length() - typedSequence.length());
    float score = logScore(bucket.counts[i]) * prefixScoreMultiplier(typedSequence) - extraLetters * PREFIX_EXTRA_LETTER_PENALTY;
    insertScoredCandidate(prefixWords, prefixScores, word, score);
  }

  for (int i = 0; i < prefixWords.length; i++)
  {
    if (prefixWords[i] != null && prefixWords[i].length() > 0)
      appendCandidate(result, prefixWords[i]);
  }
}

float prefixScoreMultiplier(String sequence)
{
  if (sequence != null && sequence.length() == 1)
    return SINGLE_GROUP_PREFIX_MULTIPLIER;
  return PREFIX_SCORE_MULTIPLIER;
}

boolean candidateAlreadyPresent(String[] words, String word)
{
  if (word == null)
    return false;

  for (int i = 0; i < words.length; i++)
  {
    if (word.equals(words[i]))
      return true;
  }
  return false;
}

void appendCandidate(String[] words, String word)
{
  if (word == null || word.length() == 0 || candidateAlreadyPresent(words, word))
    return;

  for (int i = 0; i < words.length; i++)
  {
    if (words[i] == null || words[i].length() == 0)
    {
      words[i] = word;
      return;
    }
  }
}

void insertScoredCandidate(String[] words, float[] scores, String word, float score)
{
  if (word == null || word.length() == 0)
    return;

  for (int i = 0; i < words.length; i++)
  {
    if (word.equals(words[i]))
    {
      if (score > scores[i])
        scores[i] = score;
      sortCandidateArrays(words, scores);
      return;
    }
  }

  for (int i = 0; i < words.length; i++)
  {
    if (words[i] == null || score > scores[i])
    {
      for (int j = words.length - 1; j > i; j--)
      {
        words[j] = words[j - 1];
        scores[j] = scores[j - 1];
      }
      words[i] = word;
      scores[i] = score;
      return;
    }
  }
}

void sortCandidateArrays(String[] words, float[] scores)
{
  for (int i = 0; i < scores.length; i++)
  {
    for (int j = i + 1; j < scores.length; j++)
    {
      if (scores[j] > scores[i])
      {
        float scoreSwap = scores[i];
        scores[i] = scores[j];
        scores[j] = scoreSwap;

        String wordSwap = words[i];
        words[i] = words[j];
        words[j] = wordSwap;
      }
    }
  }
}

void clearVisibleCandidates()
{
  for (int i = 0; i < visibleCandidates.length; i++)
    visibleCandidates[i] = "";
}

int visibleCandidateCount()
{
  int count = 0;
  for (int i = 0; i < visibleCandidates.length; i++)
  {
    if (visibleCandidates[i] != null && visibleCandidates[i].length() > 0)
      count++;
  }
  return count;
}

void syncCurrentTyped()
{
  if (t9Sequence.length() > 0)
    currentTyped = committedTyped + livePrediction;
  else
    currentTyped = committedTyped;
}

String previousCommittedWord()
{
  if (committedTyped.length() == 0)
    return "";

  int end = committedTyped.length() - 1;
  while (end >= 0 && committedTyped.charAt(end) == ' ')
    end--;

  if (end < 0)
    return "";

  int start = end;
  while (start >= 0 && committedTyped.charAt(start) != ' ')
    start--;

  return committedTyped.substring(start + 1, end + 1).toLowerCase();
}

String alternateCandidateLabel()
{
  String label = "";
  for (int offset = 1; offset < visibleCandidates.length; offset++)
  {
    int i = (selectedCandidateIndex + offset) % visibleCandidates.length;
    String candidate = visibleCandidates[i];
    if (candidate == null || candidate.length() == 0)
      continue;

    if (label.length() > 0)
      label += "  ";
    label += candidate;
  }
  return label;
}

int hoveredAction()
{
  if (mousePressed)
    return ACTION_NONE;
  return touchActionAt(mouseX, mouseY);
}

int touchActionAt(float x, float y)
{
  return actionAt(x, y);
}

boolean actionEnabled(int action)
{
  if (action == ACTION_NONE)
    return false;
  if (isPredictionAction(action))
    return predictionEnabled(action - ACTION_PREDICT_BASE);
  return true;
}

int actionAt(float x, float y)
{
  if (!isInsideInput(x, y))
    return ACTION_NONE;

  if (y <= inputTop() + topStripHeight())
  {
    if (x >= inputLeft() && x < inputLeft() + keyboardCellWidth())
      return ACTION_DELETE;

    int predictionIndex = predictionIndexAt(x, y);
    if (predictionIndex >= 0)
      return ACTION_PREDICT_BASE + predictionIndex;
    return ACTION_NONE;
  }

  int row = constrain((int)((y - keyboardTop()) / keyboardCellHeight()), 0, 2);
  int col = constrain((int)((x - inputLeft()) / keyboardCellWidth()), 0, 2);
  return keyboardActionAt(row, col);
}

int keyboardActionAt(int row, int col)
{
  if (row == 0)
    return ACTION_T9_BASE + col;

  if (row == 1)
    return ACTION_T9_BASE + col + 3;

  if (col == 0)
    return ACTION_T9_BASE + 6;
  if (col == 1)
    return ACTION_SPACE;
  return ACTION_T9_BASE + 7;
}

int homeButtonColor(int action, boolean enabled, boolean isPressed)
{
  if (!enabled)
    return color(78);

  if (isPressed)
    return color(246, 206, 92);

  if (action == ACTION_DELETE)
    return color(118);
  if (action == ACTION_SPACE)
    return color(175);
  if (isPredictionAction(action))
    return color(88, 116, 132);
  return color(90);
}

boolean isPredictionAction(int action)
{
  return action >= ACTION_PREDICT_BASE && action < ACTION_PREDICT_BASE + PREDICTION_TILE_COUNT;
}

boolean predictionEnabled(int index)
{
  return index >= 0 && index < visibleCandidates.length && visibleCandidates[index] != null && visibleCandidates[index].length() > 0;
}

int predictionIndexAt(float x, float y)
{
  if (x < predictionAreaLeft() || x > inputLeft() + sizeOfInputArea)
    return -1;
  if (y < inputTop() || y > inputTop() + topStripHeight())
    return -1;

  int col = constrain((int)((x - predictionAreaLeft()) / predictionTileWidth()), 0, 1);
  int row = constrain((int)((y - inputTop()) / predictionTileHeight()), 0, 1);
  int index = row * 2 + col;
  if (index < 0 || index >= PREDICTION_TILE_COUNT)
    return -1;
  return index;
}

boolean isInsideInput(float x, float y)
{
  return x >= inputLeft() && x <= inputLeft() + sizeOfInputArea && y >= inputTop() && y <= inputTop() + sizeOfInputArea;
}

float inputLeft()
{
  return width / 2.0 - sizeOfInputArea / 2.0;
}

float inputTop()
{
  return height / 2.0 - sizeOfInputArea / 2.0;
}

float buttonInset()
{
  return 3;
}

float topStripHeight()
{
  return sizeOfInputArea * 0.30;
}

float keyboardTop()
{
  return inputTop() + topStripHeight();
}

float keyboardCellWidth()
{
  return sizeOfInputArea / 3.0;
}

float keyboardCellHeight()
{
  return (sizeOfInputArea - topStripHeight()) / 3.0;
}

float keyboardCellLeft(int col)
{
  return inputLeft() + col * keyboardCellWidth();
}

float keyboardCellTop(int row)
{
  return keyboardTop() + row * keyboardCellHeight();
}

float predictionAreaLeft()
{
  return inputLeft() + keyboardCellWidth();
}

float predictionAreaWidth()
{
  return sizeOfInputArea - keyboardCellWidth();
}

float predictionTileWidth()
{
  return predictionAreaWidth() / 2.0;
}

float predictionTileHeight()
{
  return topStripHeight() / 2.0;
}

float predictionTileLeft(int index)
{
  return predictionAreaLeft() + (index % 2) * predictionTileWidth();
}

float predictionTileTop(int index)
{
  return inputTop() + (index / 2) * predictionTileHeight();
}

int predictionTileLabelSize(String label)
{
  if (label == null)
    return 7;
  if (label.length() <= 4)
    return 8;
  if (label.length() <= 8)
    return 7;
  return 6;
}

String fitLabel(String label, float maxWidth, int minSize)
{
  if (label == null || label.length() == 0)
    return "";

  textSize(minSize);
  if (textWidth(label) <= maxWidth)
    return label;

  for (int keep = label.length() - 1; keep >= 2; keep--)
  {
    String candidate = label.substring(0, keep) + ".";
    if (textWidth(candidate) <= maxWidth)
      return candidate;
  }

  return label.substring(0, 1);
}

void drawFittedLeftText(String label, float x, float y, float maxWidth, int maxSize, int minSize)
{
  if (label == null)
    label = "";

  int chosenSize = maxSize;
  for (int size = maxSize; size >= minSize; size--)
  {
    textSize(size);
    if (textWidth(label) <= maxWidth)
    {
      chosenSize = size;
      break;
    }
  }

  textSize(chosenSize);
  String fitted = label;
  if (textWidth(fitted) > maxWidth)
  {
    for (int keep = fitted.length() - 1; keep >= 2; keep--)
    {
      String candidate = fitted.substring(0, keep) + ".";
      if (textWidth(candidate) <= maxWidth)
      {
        fitted = candidate;
        break;
      }
    }
  }
  text(fitted, x, y);
}

void loadLanguageModel()
{
  println("Loading T9 language model...");
  loadDictionaryWordSet();
  loadSequenceBuckets();
  loadCountBigWords();
  loadDictionaryWords();
  loadContextSequenceBuckets();
  loadLetterNgrams();
  println("Loaded " + sequenceBuckets.size() + " T9 sequences, " + prefixSequenceBuckets.size() + " prefix sequences, " + contextSequenceBuckets.size() + " context sequences, " + nextWordBuckets.size() + " next-word buckets, and " + letterNgramScores.size() + " letter n-grams.");
}

void loadDictionaryWordSet()
{
  rememberDictionaryWords("enable1.txt");
  rememberDictionaryWords("TWL06.txt");
  dictionaryWords.put("a", true);
  dictionaryWords.put("i", true);
}

void rememberDictionaryWords(String path)
{
  BufferedReader reader = createReader(path);
  String line = null;

  try
  {
    if (reader == null)
      return;

    while ((line = reader.readLine()) != null)
    {
      String word = line.trim().toLowerCase();
      if (isLowerAlphaWord(word))
        dictionaryWords.put(word, true);
    }
  }
  catch (Exception e)
  {
    println("Could not read dictionary word set from " + path);
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void loadSequenceBuckets()
{
  BufferedReader reader = createReader("count_1w.txt");
  String line = null;
  int loadedWords = 0;

  try
  {
    if (reader == null)
      return;

    while ((line = reader.readLine()) != null && loadedWords < MAX_UNIGRAM_WORDS)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String word = line.substring(0, tab).trim().toLowerCase();
      if (!isLowerAlphaWord(word))
        continue;
      if (!isTrustedPredictionWord(word))
        continue;

      long count = parseLongSafe(line.substring(tab + 1));
      if (count <= 0)
        continue;

      addWordCandidate(word, count);

      loadedWords++;
    }
  }
  catch (Exception e)
  {
    println("Could not load count_1w.txt");
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void loadCountBigWords()
{
  BufferedReader reader = createReader("count_big.txt");
  String line = null;

  try
  {
    if (reader == null)
      return;

    while ((line = reader.readLine()) != null)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String word = line.substring(0, tab).trim().toLowerCase();
      if (!isLowerAlphaWord(word))
        continue;
      if (!isTrustedPredictionWord(word))
        continue;

      long count = parseLongSafe(line.substring(tab + 1));
      if (count <= 0)
        continue;

      addWordCandidate(word, scaledCount(count, COUNT_BIG_MULTIPLIER));
    }
  }
  catch (Exception e)
  {
    println("Could not load count_big.txt");
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void loadDictionaryWords()
{
  loadDictionaryFile("enable1.txt");
  loadDictionaryFile("TWL06.txt");
}

void loadDictionaryFile(String path)
{
  BufferedReader reader = createReader(path);
  String line = null;

  try
  {
    if (reader == null)
      return;

    while ((line = reader.readLine()) != null)
    {
      String word = line.trim().toLowerCase();
      if (word.length() > MAX_DICTIONARY_WORD_LENGTH || !isLowerAlphaWord(word))
        continue;

      dictionaryWords.put(word, true);
      addWordCandidate(word, DICTIONARY_WORD_COUNT);
    }
  }
  catch (Exception e)
  {
    println("Could not load " + path);
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void loadContextSequenceBuckets()
{
  BufferedReader reader = createReader("count_2w.txt");
  String line = null;

  try
  {
    if (reader == null)
      return;

    while ((line = reader.readLine()) != null)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String pair = line.substring(0, tab).trim().toLowerCase();
      int space = pair.indexOf(' ');
      if (space <= 0 || space >= pair.length() - 1)
        continue;
      if (pair.indexOf(' ', space + 1) != -1)
        continue;

      String first = pair.substring(0, space);
      String second = pair.substring(space + 1);
      if (!isLowerAlphaWord(first) || !isLowerAlphaWord(second))
        continue;
      if (!isTrustedPredictionWord(first) || !isTrustedPredictionWord(second))
        continue;

      long count = parseLongSafe(line.substring(tab + 1));
      if (count <= 0)
        continue;

      addContextCandidate(first, second, count);
    }
  }
  catch (Exception e)
  {
    println("Could not load count_2w.txt");
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void loadLetterNgrams()
{
  loadLetterNgramFile("count_2l.txt", 2);
  loadLetterNgramFile("count_3l.txt", 3);
}

void loadLetterNgramFile(String path, int ngramLength)
{
  BufferedReader reader = createReader(path);
  String line = null;

  try
  {
    if (reader == null)
      return;

    while ((line = reader.readLine()) != null)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String ngram = line.substring(0, tab).trim().toLowerCase();
      if (ngram.length() != ngramLength || !isLowerAlphaWord(ngram))
        continue;

      long count = parseLongSafe(line.substring(tab + 1));
      if (count <= 0)
        continue;

      letterNgramScores.put(ngram, logScore(count));
    }
  }
  catch (Exception e)
  {
    println("Could not load " + path);
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void addWordCandidate(String word, long count)
{
  String sequence = t9SequenceForWord(word);
  if (sequence.length() == word.length())
  {
    bucketFor(sequenceBuckets, sequence).consider(word, count);
    fallbackPredictionBucket.consider(word, count);
    rememberSequencePrefixes(sequence, count);
    rememberPrefixCandidates(word, sequence, count);
  }
}

void addContextCandidate(String previousWord, String word, long count)
{
  String sequence = t9SequenceForWord(word);
  if (sequence.length() == word.length())
  {
    bucketFor(contextSequenceBuckets, contextKey(previousWord, sequence)).consider(word, count);
    rememberContextPrefixCandidates(contextPrefixSequenceBuckets, previousWord, word, sequence, count);
    bucketFor(nextWordBuckets, previousWord).consider(word, count);
  }
}

void rememberContextPrefixCandidates(HashMap<String, CandidateBucket> map, String context, String word, String sequence, long count)
{
  if (context == null || context.length() == 0)
    return;

  for (int len = 1; len < sequence.length(); len++)
  {
    String prefix = sequence.substring(0, len);
    bucketFor(map, contextKey(context, prefix)).consider(word, count);
  }
}

void rememberSequencePrefixes(String sequence, long count)
{
  for (int len = 1; len < sequence.length(); len++)
  {
    String prefix = sequence.substring(0, len);
    Long current = sequencePrefixCounts.get(prefix);
    if (current == null || count > current.longValue())
      sequencePrefixCounts.put(prefix, count);
  }
}

void rememberPrefixCandidates(String word, String sequence, long count)
{
  for (int len = 1; len < sequence.length(); len++)
  {
    String prefix = sequence.substring(0, len);
    bucketFor(prefixSequenceBuckets, prefix).consider(word, count);
  }
}

CandidateBucket bucketFor(HashMap<String, CandidateBucket> map, String key)
{
  CandidateBucket bucket = map.get(key);
  if (bucket == null)
  {
    bucket = new CandidateBucket();
    map.put(key, bucket);
  }
  return bucket;
}

String contextKey(String previousWord, String sequence)
{
  return previousWord + "|" + sequence;
}

String t9SequenceForWord(String word)
{
  String sequence = "";
  for (int i = 0; i < word.length(); i++)
  {
    char digit = t9DigitForLetter(word.charAt(i));
    if (digit == 0)
      return "";
    sequence += digit;
  }
  return sequence;
}

char t9DigitForLetter(char c)
{
  if (c >= 'a' && c <= 'c')
    return '2';
  if (c >= 'd' && c <= 'f')
    return '3';
  if (c >= 'g' && c <= 'i')
    return '4';
  if (c >= 'j' && c <= 'l')
    return '5';
  if (c >= 'm' && c <= 'o')
    return '6';
  if (c >= 'p' && c <= 's')
    return '7';
  if (c >= 't' && c <= 'v')
    return '8';
  if (c >= 'w' && c <= 'z')
    return '9';
  return 0;
}

String fallbackWordFromSequence(String sequence)
{
  String ngramGuess = fallbackWordFromLetterNgrams(sequence);
  if (ngramGuess.length() > 0)
    return ngramGuess;

  String word = "";
  for (int i = 0; i < sequence.length(); i++)
  {
    int keyIndex = sequence.charAt(i) - '2';
    if (keyIndex >= 0 && keyIndex < T9_LETTERS.length)
      word += T9_LETTERS[keyIndex].charAt(0);
  }
  return word;
}

String fallbackWordFromLetterNgrams(String sequence)
{
  if (sequence.length() == 0 || letterNgramScores.size() == 0)
    return "";

  String[] beamWords = new String[BEAM_WIDTH];
  float[] beamScores = new float[BEAM_WIDTH];
  beamWords[0] = "";
  beamScores[0] = 0;
  int beamCount = 1;

  for (int i = 0; i < sequence.length(); i++)
  {
    int keyIndex = sequence.charAt(i) - '2';
    if (keyIndex < 0 || keyIndex >= T9_LETTERS.length)
      return "";

    String letters = T9_LETTERS[keyIndex];
    String[] nextWords = new String[BEAM_WIDTH];
    float[] nextScores = new float[BEAM_WIDTH];
    for (int j = 0; j < nextScores.length; j++)
      nextScores[j] = -999999;

    for (int beamIndex = 0; beamIndex < beamCount; beamIndex++)
    {
      String base = beamWords[beamIndex];
      if (base == null)
        continue;

      for (int letterIndex = 0; letterIndex < letters.length(); letterIndex++)
      {
        char next = letters.charAt(letterIndex);
        String candidate = base + next;
        float score = beamScores[beamIndex] + letterTransitionScore(base, next);
        insertBeamCandidate(nextWords, nextScores, candidate, score);
      }
    }

    beamWords = nextWords;
    beamScores = nextScores;
    beamCount = 0;
    for (int j = 0; j < beamWords.length; j++)
    {
      if (beamWords[j] != null)
        beamCount++;
    }
  }

  if (beamWords[0] == null)
    return "";
  return beamWords[0];
}

float letterTransitionScore(String prefix, char next)
{
  if (prefix.length() == 0)
    return 0;

  float score = -4.0;

  String bigram = prefix.substring(prefix.length() - 1) + next;
  Float bigramScore = letterNgramScores.get(bigram);
  if (bigramScore != null)
    score = bigramScore * 0.75;

  if (prefix.length() >= 2)
  {
    String trigram = prefix.substring(prefix.length() - 2) + next;
    Float trigramScore = letterNgramScores.get(trigram);
    if (trigramScore != null)
      score += trigramScore * 1.20;
  }

  if (isVowel(next))
    score += 0.10;
  return score;
}

boolean isVowel(char c)
{
  return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u';
}

void insertBeamCandidate(String[] words, float[] scores, String word, float score)
{
  for (int i = 0; i < words.length; i++)
  {
    if (words[i] == null || score > scores[i])
    {
      for (int j = words.length - 1; j > i; j--)
      {
        words[j] = words[j - 1];
        scores[j] = scores[j - 1];
      }
      words[i] = word;
      scores[i] = score;
      return;
    }
  }
}

boolean isLowerAlphaWord(String value)
{
  if (value == null || value.length() == 0)
    return false;

  for (int i = 0; i < value.length(); i++)
  {
    char c = value.charAt(i);
    if (c < 'a' || c > 'z')
      return false;
  }
  return true;
}

boolean isTrustedPredictionWord(String word)
{
  return dictionaryWords.size() == 0 || dictionaryWords.get(word) != null;
}

long scaledCount(long count, long multiplier)
{
  if (count > Long.MAX_VALUE / multiplier)
    return Long.MAX_VALUE;
  return count * multiplier;
}

long parseLongSafe(String value)
{
  try
  {
    return Long.parseLong(value.trim());
  }
  catch (Exception e)
  {
    return 0;
  }
}

float logScore(long count)
{
  return (float)Math.log(count + 1.0);
}

void closeReader(BufferedReader reader)
{
  try
  {
    if (reader != null)
      reader.close();
  }
  catch (Exception e)
  {
  }
}

void nextTrial()
{
  syncCurrentTyped();

  if (currTrialNum >= totalTrialNum)
    return;

  if (startTime != 0 && finishTime == 0)
  {
    System.out.println("==================");
    System.out.println("Phrase " + (currTrialNum + 1) + " of " + totalTrialNum);
    System.out.println("Target phrase: " + currentPhrase);
    System.out.println("Phrase length: " + currentPhrase.length());
    System.out.println("User typed: " + currentTyped);
    System.out.println("User typed length: " + currentTyped.length());
    System.out.println("Number of errors: " + computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim()));
    System.out.println("Time taken on this trial: " + (millis() - lastTime));
    System.out.println("Time taken since beginning: " + (millis() - startTime));
    System.out.println("==================");
    lettersExpectedTotal += currentPhrase.trim().length();
    lettersEnteredTotal += currentTyped.trim().length();
    errorsTotal += computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim());
  }

  if (currTrialNum == totalTrialNum - 1)
  {
    finishTime = millis();
    System.out.println("==================");
    System.out.println("Trials complete!");
    System.out.println("Total time taken: " + (finishTime - startTime));
    System.out.println("Total letters entered: " + lettersEnteredTotal);
    System.out.println("Total letters expected: " + lettersExpectedTotal);
    System.out.println("Total errors entered: " + errorsTotal);

    float wpm = (lettersEnteredTotal / 5.0f) / ((finishTime - startTime) / 60000f);
    float freebieErrors = lettersExpectedTotal * .05;
    float penalty = max(errorsTotal - freebieErrors, 0) * .5f;

    System.out.println("Raw WPM: " + wpm);
    System.out.println("Freebie errors: " + freebieErrors);
    System.out.println("Penalty: " + penalty);
    System.out.println("WPM w/ penalty: " + (wpm - penalty));
    System.out.println("==================");

    currTrialNum++;
    return;
  }

  if (startTime == 0)
  {
    System.out.println("Trials beginning! Starting timer...");
    startTime = millis();
  }
  else
    currTrialNum++;

  lastTime = millis();
  committedTyped = "";
  t9Sequence = "";
  livePrediction = "";
  clearVisibleCandidates();
  currentTyped = "";
  currentPhrase = phrases[currTrialNum];
}

void drawWatch()
{
  float watchscale = DPIofYourDeviceScreen / 138.0;
  pushMatrix();
  translate(width / 2, height / 2);
  scale(watchscale);
  imageMode(CENTER);
  image(watch, 0, 0);
  popMatrix();
}

int computeLevenshteinDistance(String phrase1, String phrase2)
{
  int[][] distance = new int[phrase1.length() + 1][phrase2.length() + 1];

  for (int i = 0; i <= phrase1.length(); i++)
    distance[i][0] = i;
  for (int j = 1; j <= phrase2.length(); j++)
    distance[0][j] = j;

  for (int i = 1; i <= phrase1.length(); i++)
    for (int j = 1; j <= phrase2.length(); j++)
      distance[i][j] = min(min(distance[i - 1][j] + 1, distance[i][j - 1] + 1), distance[i - 1][j - 1] + ((phrase1.charAt(i - 1) == phrase2.charAt(j - 1)) ? 0 : 1));

  return distance[phrase1.length()][phrase2.length()];
}

class CandidateBucket
{
  String[] words = new String[BUCKET_CAPACITY];
  long[] counts = new long[BUCKET_CAPACITY];

  void consider(String word, long count)
  {
    if (word == null || word.length() == 0)
      return;

    for (int i = 0; i < words.length; i++)
    {
      if (word.equals(words[i]))
      {
        if (count > counts[i])
        {
          counts[i] = count;
          bubbleUp(i);
        }
        return;
      }
    }

    for (int i = 0; i < words.length; i++)
    {
      if (words[i] == null || count > counts[i])
      {
        shiftDownFrom(i);
        words[i] = word;
        counts[i] = count;
        return;
      }
    }
  }

  void shiftDownFrom(int index)
  {
    for (int i = words.length - 1; i > index; i--)
    {
      words[i] = words[i - 1];
      counts[i] = counts[i - 1];
    }
  }

  void bubbleUp(int index)
  {
    for (int i = index; i > 0; i--)
    {
      if (counts[i] <= counts[i - 1])
        return;

      String wordSwap = words[i];
      words[i] = words[i - 1];
      words[i - 1] = wordSwap;

      long countSwap = counts[i];
      counts[i] = counts[i - 1];
      counts[i - 1] = countSwap;
    }
  }

  long countFor(String word)
  {
    if (word == null)
      return 0;

    for (int i = 0; i < words.length; i++)
    {
      if (word.equals(words[i]))
        return counts[i];
    }
    return 0;
  }
}

class SegPath
{
  String text;
  String lastWord;
  float score;
  int wordCount;

  SegPath(String text, String lastWord, float score, int wordCount)
  {
    this.text = text;
    this.lastWord = lastWord;
    this.score = score;
    this.wordCount = wordCount;
  }
}
