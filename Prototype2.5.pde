import java.io.BufferedReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.Random;
import java.util.HashMap;
import java.util.HashSet;
import java.util.ArrayList;

// Set the DPI to make your smartwatch 1 inch square. Measure it on the screen
final int DPIofYourDeviceScreen = 125;

// Do not change the following variables
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

// QWERTY-like grouped keyboard.
final String[] GROUPS = {
  "qwe", "rty", "uiop",
  "asd", "fgh", "jkl",
  "zxc", "vbnm"
};

final String ALPHABET = "abcdefghijklmnopqrstuvwxyz";

final int ACTION_NONE = 0;
final int ACTION_DELETE = 1;
final int ACTION_SPACE = 2;
final int ACTION_HOT_0 = 3;
final int ACTION_HOT_1 = 4;
final int ACTION_HOT_2 = 5;
final int ACTION_GROUP_BASE = 100;

final int HOT_TILE_COUNT = 3;
final int HOT_EMPTY = 0;
final int HOT_LETTER = 1;
final int HOT_CHUNK = 2;
final int HOT_WORD = 3;
final int HOT_CLUSTER = 4;

final int PREFIX_LIMIT = 10;
final int MAX_UNIGRAM_WORDS = 70000;
final int WORD_BUCKET_CAPACITY = 10;
final int CHAR_BUCKET_CAPACITY = 6;
final int WORD_CLUSTER_LIMIT = 4;
final int FALLBACK_WORD_COUNT = 12;
final int COMMON_BIGRAM_COUNT = 8;
final int COMMON_TRIGRAM_COUNT = 8;
final float HOT_WORD_CONFIDENCE = 1.85;

HashMap<String, Long> wordFreq = new HashMap<String, Long>();
HashMap<String, WordBucket> prefixBuckets = new HashMap<String, WordBucket>();
HashMap<String, WordBucket> bigramBuckets = new HashMap<String, WordBucket>();
HashMap<String, CharBucket> nextLetter1 = new HashMap<String, CharBucket>();
HashMap<String, CharBucket> nextLetter2 = new HashMap<String, CharBucket>();
HashMap<String, Float> editWeights = new HashMap<String, Float>();
HashSet<String> dictionary = new HashSet<String>();

String[] fallbackWords = new String[FALLBACK_WORD_COUNT];
String[] commonBigrams = new String[COMMON_BIGRAM_COUNT];
String[] commonTrigrams = new String[COMMON_TRIGRAM_COUNT];
int commonBigramCount = 0;
int commonTrigramCount = 0;

HotTile[] hotTiles = new HotTile[HOT_TILE_COUNT];

int activeGroup = -1;
String activeGroupLetters = "";
String[] activeWordOptions = new String[WORD_CLUSTER_LIMIT];
int activeWordOptionCount = 0;
int activeTapAction = ACTION_NONE;

void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());
  initHotTiles();
  loadLanguageModel();

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
  fill(34);
  rect(inputLeft(), inputTop(), sizeOfInputArea, sizeOfInputArea, 18);
  fill(50);
  rect(inputLeft() + 4, inputTop() + 4, sizeOfInputArea - 8, sizeOfInputArea - 8, 15);

  if (activeGroup >= 0)
    drawLetterSelectionMode();
  else if (activeWordOptionCount > 0)
    drawWordClusterMode();
  else
    drawHomeKeyboard();
}

void drawHomeKeyboard()
{
  refreshHotTiles();
  textAlign(CENTER, CENTER);

  for (int i = 0; i < 4; i++)
  {
    int action = topActionAtIndex(i);
    float x = topTileLeft(i) + buttonInset();
    float y = inputTop() + buttonInset();
    float w = topTileWidth() - buttonInset() * 2;
    float h = topStripHeight() - buttonInset() * 2;
    boolean isPressed = action == activeTapAction;
    boolean enabled = actionEnabled(action);

    fill(homeButtonColor(action, enabled, isPressed));
    rect(x, y, w, h, 10);

    if (action == ACTION_DELETE)
      drawDeleteTile(x, y, w, h, isPressed);
    else
      drawHotTile(i - 1, x, y, w, h, isPressed, enabled);
  }

  for (int row = 0; row < 3; row++)
  {
    for (int col = 0; col < 3; col++)
    {
      int action = keyboardActionAt(row, col);
      float x = keyboardCellLeft(col) + buttonInset();
      float y = keyboardCellTop(row) + buttonInset();
      float w = keyboardCellWidth() - buttonInset() * 2;
      float h = keyboardCellHeight() - buttonInset() * 2;
      boolean enabled = actionEnabled(action);
      boolean isPressed = action == activeTapAction;

      fill(homeButtonColor(action, enabled, isPressed));
      rect(x, y, w, h, 10);

      if (action >= ACTION_GROUP_BASE)
        drawGroupPreview(action - ACTION_GROUP_BASE, x, y, w, h, isPressed);
      else
        drawSpecialKey(action, x, y, w, h, isPressed);
    }
  }
}

void drawDeleteTile(float x, float y, float w, float h, boolean isPressed)
{
  fill(isPressed ? color(20) : color(248));
  textSize(12);
  text("del", x + w / 2, y + h / 2 + 1);
}

void drawSpecialKey(int action, float x, float y, float w, float h, boolean isPressed)
{
  fill(isPressed ? color(20) : color(248));
  textSize(action == ACTION_SPACE ? 11 : 12);
  if (action == ACTION_SPACE)
    text("space", x + w / 2, y + h / 2 + 1);
}

void drawHotTile(int tileIndex, float x, float y, float w, float h, boolean isPressed, boolean enabled)
{
  HotTile tile = hotTiles[tileIndex];
  if (!enabled || tile.kind == HOT_EMPTY)
    return;

  if (tile.kind == HOT_CLUSTER)
  {
    float cardHeight = tile.optionCount == 1 ? h * 0.52 : h * 0.24;
    float gap = h * 0.06;
    float totalHeight = tile.optionCount * cardHeight + (tile.optionCount - 1) * gap;
    float startY = y + (h - totalHeight) / 2.0;

    for (int i = 0; i < tile.optionCount && i < 3; i++)
    {
      float cardY = startY + i * (cardHeight + gap);
      fill(isPressed ? color(255, 240, 188) : color(118, 144, 160));
      rect(x + w * 0.10, cardY, w * 0.80, cardHeight, 5);
      fill(isPressed ? color(20) : color(248));
      textSize(7);
      text(drawChoiceLabel(tile.options[i], 7), x + w / 2, cardY + cardHeight / 2 + 1);
    }
    return;
  }

  fill(isPressed ? color(20) : color(248));
  textSize(tile.kind == HOT_WORD ? 9 : 12);
  text(drawLabel(tile.label, tile.kind == HOT_WORD ? 8 : 3), x + w / 2, y + h / 2 + 1);
}

void drawLetterSelectionMode()
{
  int hoveredIndex = selectionLetterIndexAt(mouseX, mouseY, activeGroup, activeGroupLetters);

  textAlign(CENTER, CENTER);
  for (int i = 0; i < activeGroupLetters.length(); i++)
  {
    PVector slot = selectionSlotCenter(activeGroupLetters.length(), i);
    float boxWidth = selectionBoxWidth(activeGroupLetters.length());
    float boxHeight = selectionBoxHeight(activeGroupLetters.length());
    boolean isHovered = i == hoveredIndex;

    fill(isHovered ? color(246, 206, 92) : color(95));
    rect(slot.x - boxWidth / 2, slot.y - boxHeight / 2, boxWidth, boxHeight, 14);

    fill(isHovered ? color(20) : color(248));
    textSize(activeGroupLetters.length() == 4 ? 34 : 38);
    text(activeGroupLetters.charAt(i), slot.x, slot.y + 1);
  }

  fill(250);
  textSize(9);
  text("tap a letter or tap empty space to cancel", inputCenterX(), inputTop() + sizeOfInputArea - 8);
}

void drawWordClusterMode()
{
  int hoveredIndex = wordOptionIndexAt(mouseX, mouseY);

  textAlign(CENTER, CENTER);
  for (int i = 0; i < activeWordOptionCount; i++)
  {
    float[] box = wordOptionBox(i, activeWordOptionCount);
    boolean isHovered = hoveredIndex == i;

    fill(isHovered ? color(246, 206, 92) : color(92, 120, 138));
    rect(box[0], box[1], box[2], box[3], 14);

    fill(isHovered ? color(20) : color(248));
    textSize(wordChoiceLabelSize(activeWordOptions[i]));
    text(drawChoiceLabel(activeWordOptions[i], 12), box[0] + box[2] / 2, box[1] + box[3] / 2 + 1);
  }

  fill(250);
  textSize(9);
  text("tap a word or tap empty space to cancel", inputCenterX(), inputTop() + sizeOfInputArea - 8);
}

void drawOutsideUI()
{
  textAlign(LEFT, CENTER);
  fill(128);
  textSize(24);
  text("Phrase " + (currTrialNum + 1) + " of " + totalTrialNum, 70, 50);
  text("Target:   " + currentPhrase, 70, 100);
  text("Entered:  " + currentTyped + "|", 70, 140);

  fill(255);
  rect(580, 580, 180, 90, 14);
  fill(100);
  textAlign(CENTER, CENTER);
  text("NEXT >", 670, 625);
}

boolean didMouseClick(float x, float y, float w, float h)
{
  return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
}

boolean pointInRect(float px, float py, float x, float y, float w, float h)
{
  return px >= x && px <= x + w && py >= y && py <= y + h;
}

void mousePressed()
{
  if (finishTime != 0)
    return;

  if (didMouseClick(580, 580, 180, 90))
  {
    nextTrial();
    return;
  }

  if (startTime == 0)
    return;

  if (!isInsideInput(mouseX, mouseY))
    return;

  if (activeGroup >= 0 || activeWordOptionCount > 0)
    return;

  activeTapAction = actionAt(mouseX, mouseY);
}

void mouseReleased()
{
  if (activeGroup >= 0)
  {
    handleLetterSelection(mouseX, mouseY);
    activeGroup = -1;
    activeGroupLetters = "";
    return;
  }

  if (activeWordOptionCount > 0)
  {
    handleWordClusterSelection(mouseX, mouseY);
    clearWordCluster();
    return;
  }

  if (activeTapAction == ACTION_NONE)
    return;

  if (!isInsideInput(mouseX, mouseY) || actionAt(mouseX, mouseY) != activeTapAction)
  {
    activeTapAction = ACTION_NONE;
    return;
  }

  handleHomeAction(activeTapAction);
  activeTapAction = ACTION_NONE;
}

void handleHomeAction(int action)
{
  if (action == ACTION_DELETE)
  {
    if (currentTyped.length() > 0)
      currentTyped = currentTyped.substring(0, currentTyped.length() - 1);
    return;
  }

  if (action == ACTION_SPACE)
  {
    commitWordBoundary();
    return;
  }

  if (action == ACTION_HOT_0 || action == ACTION_HOT_1 || action == ACTION_HOT_2)
  {
    applyHotTile(action - ACTION_HOT_0);
    return;
  }

  if (action >= ACTION_GROUP_BASE)
  {
    activeGroup = action - ACTION_GROUP_BASE;
    activeGroupLetters = orderedLettersForGroup(activeGroup);
  }
}

void handleLetterSelection(float x, float y)
{
  int index = selectionLetterIndexAt(x, y, activeGroup, activeGroupLetters);
  if (index < 0)
    return;

  currentTyped += activeGroupLetters.charAt(index);
}

void handleWordClusterSelection(float x, float y)
{
  int index = wordOptionIndexAt(x, y);
  if (index < 0)
    return;

  applyPredictedWord(activeWordOptions[index]);
}

void applyHotTile(int tileIndex)
{
  HotTile tile = hotTiles[tileIndex];
  if (tile.kind == HOT_EMPTY)
    return;

  if (tile.kind == HOT_LETTER || tile.kind == HOT_CHUNK)
  {
    currentTyped += tile.commitText;
    return;
  }

  if (tile.kind == HOT_WORD)
  {
    applyPredictedWord(tile.commitText);
    return;
  }

  if (tile.kind == HOT_CLUSTER)
  {
    openWordCluster(tile.options, tile.optionCount);
  }
}

void applyPredictedWord(String word)
{
  if (word == null || word.length() == 0)
    return;

  String prefix = currentWordPrefix();
  if (prefix.length() > 0)
  {
    int lastSpace = currentTyped.lastIndexOf(' ');
    String base = lastSpace >= 0 ? currentTyped.substring(0, lastSpace + 1) : "";
    currentTyped = base + word;
  }
  else
  {
    currentTyped += word;
  }

  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) != ' ')
    currentTyped += " ";
}

void commitWordBoundary()
{
  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) == ' ')
    return;

  autocorrectTrailingWordInPlace();
  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) != ' ')
    currentTyped += " ";
}

void refreshHotTiles()
{
  clearHotTiles();

  String prefix = currentWordPrefix().toLowerCase();
  String previousWord = previousContextWord().toLowerCase();

  ArrayList<ScoredString> wordCandidates = collectWordCandidates(prefix, previousWord, 8);
  HashMap<Character, Float> letterScores = buildLetterScores(prefix, previousWord, wordCandidates);
  ArrayList<ScoredString> letterContinuations = sortCharScoreMap(letterScores, 6);
  ArrayList<ScoredString> chunkCandidates = buildChunkCandidates(prefix, wordCandidates, letterContinuations);

  ArrayList<HotTile> letterTiles = buildLetterTiles(letterContinuations);
  ArrayList<HotTile> chunkTiles = buildChunkTiles(chunkCandidates);
  HotTile wordTile = buildWordTile(prefix, previousWord, wordCandidates);

  ArrayList<HotTile> selected = new ArrayList<HotTile>();
  if (letterTiles.size() > 0)
    tryAddHotTile(selected, letterTiles.get(0));
  if (chunkTiles.size() > 0)
    tryAddHotTile(selected, chunkTiles.get(0));
  if (!wordTile.isEmpty())
    tryAddHotTile(selected, wordTile);

  ArrayList<HotTile> remaining = new ArrayList<HotTile>();
  for (int i = 1; i < letterTiles.size(); i++)
    tryAddHotTile(remaining, letterTiles.get(i));
  for (int i = 1; i < chunkTiles.size(); i++)
    tryAddHotTile(remaining, chunkTiles.get(i));

  sortHotTilesByScore(remaining);
  for (int i = 0; i < remaining.size() && selected.size() < HOT_TILE_COUNT; i++)
    tryAddHotTile(selected, remaining.get(i));

  placeHotTiles(selected);
}

ArrayList<HotTile> buildLetterTiles(ArrayList<ScoredString> continuations)
{
  ArrayList<HotTile> tiles = new ArrayList<HotTile>();

  for (int i = 0; i < continuations.size() && tiles.size() < HOT_TILE_COUNT; i++)
  {
    ScoredString candidate = continuations.get(i);
    if (candidate.text.length() != 1)
      continue;

    HotTile tile = new HotTile();
    tile.setDirect(HOT_LETTER, candidate.text, candidate.score);
    tiles.add(tile);
  }

  return tiles;
}

ArrayList<HotTile> buildChunkTiles(ArrayList<ScoredString> chunks)
{
  ArrayList<HotTile> tiles = new ArrayList<HotTile>();

  for (int i = 0; i < chunks.size() && tiles.size() < HOT_TILE_COUNT + 1; i++)
  {
    ScoredString candidate = chunks.get(i);
    if (candidate.text.length() < 2)
      continue;

    HotTile tile = new HotTile();
    tile.setDirect(HOT_CHUNK, candidate.text, candidate.score);
    if (!tilesConflictWithList(tiles, tile))
      tiles.add(tile);
  }

  return tiles;
}

HotTile buildWordTile(String prefix, String previousWord, ArrayList<ScoredString> words)
{
  HotTile tile = new HotTile();
  ArrayList<ScoredString> filtered = new ArrayList<ScoredString>();

  for (int i = 0; i < words.size(); i++)
    insertSorted(filtered, new ScoredString(words.get(i).text, words.get(i).score), WORD_CLUSTER_LIMIT);

  if (filtered.size() == 0)
    return tile;

  float first = filtered.get(0).score;
  float second = filtered.size() > 1 ? filtered.get(1).score : 0;
  float ratio = second > 0 ? first / second : first;

  if (prefix.length() == 0 && previousWord.length() == 0)
    return tile;

  if (prefix.length() == 0)
  {
    if (filtered.size() == 1 || ratio > HOT_WORD_CONFIDENCE + 0.45)
      tile.setDirect(HOT_WORD, filtered.get(0).text, first * 0.98);
    return tile;
  }

  if (filtered.size() == 1 || ratio > HOT_WORD_CONFIDENCE)
  {
    tile.setDirect(HOT_WORD, filtered.get(0).text, first);
    return tile;
  }

  String[] options = new String[min(filtered.size(), WORD_CLUSTER_LIMIT)];
  for (int i = 0; i < options.length; i++)
    options[i] = filtered.get(i).text;
  tile.setCluster(options, options.length, first * 0.97);
  return tile;
}

ArrayList<ScoredString> collectWordCandidates(String prefix, String previousWord, int limit)
{
  HashMap<String, Float> scoreMap = new HashMap<String, Float>();

  if (previousWord.length() > 0)
    addBucketMatches(scoreMap, bigramBuckets.get(previousWord), prefix, 1.8);

  if (prefix.length() > 0)
  {
    String key = prefix.substring(0, min(prefix.length(), PREFIX_LIMIT));
    addBucketMatches(scoreMap, prefixBuckets.get(key), prefix, 1.0);
  }
  else
  {
    for (int i = 0; i < fallbackWords.length; i++)
    {
      if (fallbackWords[i] == null)
        continue;
      long freq = wordFreq.containsKey(fallbackWords[i]) ? wordFreq.get(fallbackWords[i]) : 1;
      addScore(scoreMap, fallbackWords[i], scoreFromCount(freq, 1.0));
    }
  }

  ArrayList<ScoredString> ranked = sortScoreMap(scoreMap, limit);

  if (ranked.size() < limit)
  {
    for (int i = 0; i < fallbackWords.length; i++)
    {
      String word = fallbackWords[i];
      if (word == null)
        continue;
      if (prefix.length() > 0 && !word.startsWith(prefix))
        continue;
      insertSorted(ranked, new ScoredString(word, scoreFromCount(wordFreq.containsKey(word) ? wordFreq.get(word) : 1, 0.7)), limit);
    }
  }

  return ranked;
}

HashMap<Character, Float> buildLetterScores(String prefix, String previousWord, ArrayList<ScoredString> words)
{
  HashMap<Character, Float> scores = new HashMap<Character, Float>();

  for (int i = 0; i < words.size(); i++)
  {
    String word = words.get(i).text;
    if (word.length() <= prefix.length())
      continue;
    char next = word.charAt(prefix.length());
    addCharScore(scores, next, words.get(i).score * 1.35);
  }

  String tail2 = suffixOfAlpha(prefix, 2);
  if (tail2.length() == 2)
    addCharBucket(scores, nextLetter2.get(tail2), 0.9);

  String tail1 = suffixOfAlpha(prefix, 1);
  if (tail1.length() == 1)
    addCharBucket(scores, nextLetter1.get(tail1), 0.7);

  return scores;
}

ArrayList<ScoredString> buildChunkCandidates(String prefix, ArrayList<ScoredString> words, ArrayList<ScoredString> letterContinuations)
{
  HashMap<String, Float> chunkScores = new HashMap<String, Float>();

  for (int i = 0; i < words.size(); i++)
  {
    String word = words.get(i).text;
    if (word.length() <= prefix.length() + 1)
      continue;

    String remainder = word.substring(prefix.length());
    int maxLen = min(3, remainder.length());
    for (int len = 2; len <= maxLen; len++)
      addScore(chunkScores, remainder.substring(0, len), words.get(i).score * (len == 3 ? 1.05 : 0.95));
  }

  if (prefix.length() > 0)
    addNgramContinuationChunks(prefix, chunkScores, letterContinuations);

  if (chunkScores.size() < 3)
  {
    for (int i = 0; i < commonTrigramCount; i++)
      addScore(chunkScores, commonTrigrams[i], 3.4 - i * 0.1);
    for (int i = 0; i < commonBigramCount; i++)
      addScore(chunkScores, commonBigrams[i], 2.7 - i * 0.08);
  }

  return sortScoreMap(chunkScores, 8);
}

void addNgramContinuationChunks(String prefix, HashMap<String, Float> scores, ArrayList<ScoredString> letterContinuations)
{
  for (int i = 0; i < min(letterContinuations.size(), 3); i++)
  {
    String first = letterContinuations.get(i).text;
    if (first.length() != 1)
      continue;

    String built = prefix + first;
    char second = bestContinuationChar(built);
    if (second == 0)
      continue;

    addScore(scores, first + second, letterContinuations.get(i).score * 0.9);

    char third = bestContinuationChar(built + second);
    if (third != 0)
      addScore(scores, first + second + third, letterContinuations.get(i).score * 0.95);
  }
}

char bestContinuationChar(String current)
{
  String tail2 = suffixOfAlpha(current, 2);
  if (tail2.length() == 2 && nextLetter2.containsKey(tail2))
  {
    CharBucket bucket = nextLetter2.get(tail2);
    if (bucket.letters[0] != 0)
      return bucket.letters[0];
  }

  String tail1 = suffixOfAlpha(current, 1);
  if (tail1.length() == 1 && nextLetter1.containsKey(tail1))
  {
    CharBucket bucket = nextLetter1.get(tail1);
    if (bucket.letters[0] != 0)
      return bucket.letters[0];
  }

  return 0;
}

String orderedLettersForGroup(int groupIndex)
{
  String prefix = currentWordPrefix().toLowerCase();
  String previousWord = previousContextWord().toLowerCase();
  ArrayList<ScoredString> words = collectWordCandidates(prefix, previousWord, 8);
  HashMap<Character, Float> scores = buildLetterScores(prefix, previousWord, words);
  String group = GROUPS[groupIndex];
  ArrayList<ScoredString> ranked = new ArrayList<ScoredString>();

  for (int i = 0; i < group.length(); i++)
  {
    char c = group.charAt(i);
    float score = scores.containsKey(c) ? scores.get(c) : 0.05;
    insertSorted(ranked, new ScoredString("" + c, score), group.length());
  }

  String ordered = "";
  for (int i = 0; i < ranked.size(); i++)
    ordered += ranked.get(i).text;
  return ordered;
}

void openWordCluster(String[] options, int count)
{
  activeWordOptionCount = min(count, WORD_CLUSTER_LIMIT);
  for (int i = 0; i < activeWordOptionCount; i++)
    activeWordOptions[i] = options[i];
}

void clearWordCluster()
{
  activeWordOptionCount = 0;
  for (int i = 0; i < activeWordOptions.length; i++)
    activeWordOptions[i] = "";
}

void autocorrectTrailingWordInPlace()
{
  int end = currentTyped.length() - 1;
  while (end >= 0 && currentTyped.charAt(end) == ' ')
    end--;

  if (end < 0)
    return;

  int start = end;
  while (start >= 0 && currentTyped.charAt(start) != ' ')
    start--;

  String typedWord = currentTyped.substring(start + 1, end + 1).toLowerCase();
  String corrected = autocorrectWord(typedWord);

  if (!typedWord.equals(corrected))
    currentTyped = currentTyped.substring(0, start + 1) + corrected + currentTyped.substring(end + 1);
}

String autocorrectWord(String typedWord)
{
  if (typedWord.length() < 2 || !isAlphaWord(typedWord))
    return typedWord;

  boolean typedKnown = dictionary.contains(typedWord);
  float typedScore = typedKnown ? languageScore(typedWord) : -2.0;
  String bestWord = typedWord;
  float bestScore = typedScore;

  HashSet<String> candidates = new HashSet<String>();
  buildEdits1(typedWord, candidates);

  for (String candidate : candidates)
  {
    if (!dictionary.contains(candidate))
      continue;

    float candidateScore = languageScore(candidate) + editPatternBonus(typedWord, candidate);
    if (!typedKnown && candidateScore > bestScore + 0.45)
    {
      bestWord = candidate;
      bestScore = candidateScore;
    }
    else if (typedKnown && candidateScore > bestScore + 2.2)
    {
      bestWord = candidate;
      bestScore = candidateScore;
    }
  }

  return bestWord;
}

float languageScore(String word)
{
  long freq = wordFreq.containsKey(word) ? wordFreq.get(word) : 1;
  return logCount(freq);
}

float editPatternBonus(String typedWord, String candidate)
{
  String key = editPatternKey(typedWord, candidate);
  if (key.length() == 0 || !editWeights.containsKey(key))
    return 0;
  return log(editWeights.get(key) + 1.0) * 0.35;
}

String editPatternKey(String fromWord, String toWord)
{
  int left = 0;
  while (left < fromWord.length() && left < toWord.length() && fromWord.charAt(left) == toWord.charAt(left))
    left++;

  int fromRight = fromWord.length() - 1;
  int toRight = toWord.length() - 1;
  while (fromRight >= left && toRight >= left && fromWord.charAt(fromRight) == toWord.charAt(toRight))
  {
    fromRight--;
    toRight--;
  }

  String fromDiff = fromWord.substring(left, fromRight + 1);
  String toDiff = toWord.substring(left, toRight + 1);
  return fromDiff + "|" + toDiff;
}

void buildEdits1(String word, HashSet<String> out)
{
  for (int i = 0; i < word.length(); i++)
    out.add(word.substring(0, i) + word.substring(i + 1));

  for (int i = 0; i < word.length() - 1; i++)
    out.add(word.substring(0, i) + word.charAt(i + 1) + word.charAt(i) + word.substring(i + 2));

  for (int i = 0; i < word.length(); i++)
  {
    for (int j = 0; j < ALPHABET.length(); j++)
    {
      char c = ALPHABET.charAt(j);
      out.add(word.substring(0, i) + c + word.substring(i + 1));
    }
  }

  for (int i = 0; i <= word.length(); i++)
  {
    for (int j = 0; j < ALPHABET.length(); j++)
    {
      char c = ALPHABET.charAt(j);
      out.add(word.substring(0, i) + c + word.substring(i));
    }
  }
}

int actionAt(float x, float y)
{
  if (!isInsideInput(x, y))
    return ACTION_NONE;

  if (y <= inputTop() + topStripHeight())
  {
    int tileIndex = constrain((int)((x - inputLeft()) / topTileWidth()), 0, 3);
    return topActionAtIndex(tileIndex);
  }

  int row = constrain((int)((y - keyboardTop()) / keyboardCellHeight()), 0, 2);
  int col = constrain((int)((x - inputLeft()) / keyboardCellWidth()), 0, 2);
  return keyboardActionAt(row, col);
}

int topActionAtIndex(int tileIndex)
{
  if (tileIndex == 0)
    return ACTION_DELETE;
  return ACTION_HOT_0 + tileIndex - 1;
}

int keyboardActionAt(int row, int col)
{
  if (row == 0)
    return ACTION_GROUP_BASE + col;

  if (row == 1)
    return ACTION_GROUP_BASE + col + 3;

  if (col == 0)
    return ACTION_GROUP_BASE + 6;
  if (col == 1)
    return ACTION_SPACE;
  return ACTION_GROUP_BASE + 7;
}

boolean actionEnabled(int action)
{
  if (action >= ACTION_HOT_0 && action <= ACTION_HOT_2)
    return !hotTiles[action - ACTION_HOT_0].isEmpty();
  return true;
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
  if (action >= ACTION_HOT_0 && action <= ACTION_HOT_2)
  {
    HotTile tile = hotTiles[action - ACTION_HOT_0];
    if (tile.kind == HOT_LETTER)
      return color(96, 126, 110);
    if (tile.kind == HOT_CHUNK)
      return color(104, 118, 148);
    return color(88, 116, 132);
  }
  return color(90);
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

float inputCenterX()
{
  return width / 2.0;
}

float topStripHeight()
{
  return sizeOfInputArea * 0.22;
}

float topTileWidth()
{
  return sizeOfInputArea / 4.0;
}

float topTileLeft(int index)
{
  return inputLeft() + index * topTileWidth();
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

float buttonInset()
{
  return 3;
}

void drawGroupPreview(int groupIndex, float x, float y, float w, float h, boolean isPressed)
{
  String group = GROUPS[groupIndex];
  float tileWidth = previewBoxWidth(group.length(), w);
  float tileHeight = previewBoxHeight(group.length(), h);

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot = previewSlotCenter(group.length(), i, x, y, w, h);
    fill(isPressed ? color(255, 240, 188) : color(126));
    rect(slot.x - tileWidth / 2, slot.y - tileHeight / 2, tileWidth, tileHeight, 6);
    fill(isPressed ? color(20) : color(248));
    textSize(group.length() == 4 ? 12 : 13);
    text(group.charAt(i), slot.x, slot.y + 1);
  }
}

PVector previewSlotCenter(int groupLength, int index, float x, float y, float w, float h)
{
  float[] pos = homeSlotPosition(groupLength, index);
  return new PVector(x + w * pos[0], y + h * pos[1]);
}

PVector selectionSlotCenter(int groupLength, int index)
{
  float[] pos = selectionSlotPosition(groupLength, index);
  float marginX = sizeOfInputArea * 0.10;
  float marginY = sizeOfInputArea * 0.10;
  return new PVector(inputLeft() + marginX + (sizeOfInputArea - marginX * 2) * pos[0], inputTop() + marginY + (sizeOfInputArea - marginY * 2) * pos[1]);
}

float[] homeSlotPosition(int groupLength, int index)
{
  if (groupLength == 4)
  {
    if (index == 0) return new float[] {0.28, 0.28};
    if (index == 1) return new float[] {0.72, 0.28};
    if (index == 2) return new float[] {0.28, 0.72};
    return new float[] {0.72, 0.72};
  }

  if (index == 0) return new float[] {0.28, 0.32};
  if (index == 1) return new float[] {0.72, 0.32};
  return new float[] {0.50, 0.74};
}

float[] selectionSlotPosition(int groupLength, int index)
{
  if (groupLength == 4)
  {
    if (index == 0) return new float[] {0.10, 0.10};
    if (index == 1) return new float[] {0.90, 0.10};
    if (index == 2) return new float[] {0.10, 0.90};
    return new float[] {0.90, 0.90};
  }

  if (index == 0) return new float[] {0.10, 0.15};
  if (index == 1) return new float[] {0.90, 0.15};
  return new float[] {0.50, 0.90};
}

float previewBoxWidth(int groupLength, float keyWidth)
{
  return groupLength == 4 ? keyWidth * 0.28 : keyWidth * 0.32;
}

float previewBoxHeight(int groupLength, float keyHeight)
{
  return groupLength == 4 ? keyHeight * 0.24 : keyHeight * 0.26;
}

float selectionBoxWidth(int groupLength)
{
  return groupLength == 4 ? sizeOfInputArea * 0.22 : sizeOfInputArea * 0.26;
}

float selectionBoxHeight(int groupLength)
{
  return groupLength == 4 ? sizeOfInputArea * 0.22 : sizeOfInputArea * 0.22;
}

int selectionLetterIndexAt(float x, float y, int groupIndex, String letters)
{
  for (int i = 0; i < letters.length(); i++)
  {
    PVector slot = selectionSlotCenter(letters.length(), i);
    float boxWidth = selectionBoxWidth(letters.length());
    float boxHeight = selectionBoxHeight(letters.length());
    if (pointInRect(x, y, slot.x - boxWidth / 2, slot.y - boxHeight / 2, boxWidth, boxHeight))
      return i;
  }

  return -1;
}

float[] wordOptionBox(int optionIndex, int optionCount)
{
  float boxWidth = sizeOfInputArea * 0.74;
  float boxHeight = optionCount == 1 ? sizeOfInputArea * 0.28 : sizeOfInputArea * 0.20;
  float gap = sizeOfInputArea * 0.06;
  float totalHeight = optionCount * boxHeight + (optionCount - 1) * gap;
  float startY = inputTop() + (sizeOfInputArea - totalHeight) / 2.0;
  float x = inputLeft() + (sizeOfInputArea - boxWidth) / 2.0;
  float y = startY + optionIndex * (boxHeight + gap);
  return new float[] {x, y, boxWidth, boxHeight};
}

int wordOptionIndexAt(float x, float y)
{
  for (int i = 0; i < activeWordOptionCount; i++)
  {
    float[] box = wordOptionBox(i, activeWordOptionCount);
    if (pointInRect(x, y, box[0], box[1], box[2], box[3]))
      return i;
  }

  return -1;
}

String drawChoiceLabel(String label, int maxChars)
{
  if (label == null || label.length() == 0)
    return " ";
  if (label.length() <= maxChars)
    return label;
  return label.substring(0, maxChars);
}

String drawLabel(String label, int maxChars)
{
  if (label == null || label.length() == 0)
    return " ";
  if (label.length() <= maxChars)
    return label;
  return label.substring(0, maxChars);
}

float wordChoiceLabelSize(String word)
{
  if (word == null) return 18;
  if (word.length() <= 5) return 20;
  if (word.length() <= 8) return 18;
  return 16;
}

void initHotTiles()
{
  for (int i = 0; i < hotTiles.length; i++)
    hotTiles[i] = new HotTile();
}

void clearHotTiles()
{
  for (int i = 0; i < hotTiles.length; i++)
    hotTiles[i] = new HotTile();
}

void loadLanguageModel()
{
  loadWordsAndPrefixes();
  loadBigrams();
  loadLetterNgrams();
  loadEditPatterns();
  loadDictionary("ngrams/enable1.txt");
  loadDictionary("ngrams/TWL06.txt");
}

void loadWordsAndPrefixes()
{
  BufferedReader reader = createReader("ngrams/count_1w.txt");
  String line = null;
  int loaded = 0;
  int fallbackIndex = 0;

  try
  {
    while ((line = reader.readLine()) != null && loaded < MAX_UNIGRAM_WORDS)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String word = line.substring(0, tab).trim().toLowerCase();
      if (!isAlphaWord(word))
        continue;

      long count = parseCount(line.substring(tab + 1));
      if (count <= 0)
        continue;

      wordFreq.put(word, count);

      if (fallbackIndex < fallbackWords.length)
        fallbackWords[fallbackIndex++] = word;

      int maxPrefix = min(PREFIX_LIMIT, word.length());
      for (int len = 1; len <= maxPrefix; len++)
        bucketFor(prefixBuckets, word.substring(0, len)).consider(word, count);

      loaded++;
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

void loadBigrams()
{
  BufferedReader reader = createReader("ngrams/count_2w.txt");
  String line = null;

  try
  {
    while ((line = reader.readLine()) != null)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String pair = line.substring(0, tab).trim().toLowerCase();
      int spaceIndex = pair.indexOf(' ');
      if (spaceIndex <= 0 || spaceIndex >= pair.length() - 1)
        continue;
      if (pair.indexOf(' ', spaceIndex + 1) != -1)
        continue;

      String first = pair.substring(0, spaceIndex);
      String second = pair.substring(spaceIndex + 1);
      if (!isAlphaWord(first) || !isAlphaWord(second))
        continue;

      long count = parseCount(line.substring(tab + 1));
      if (count <= 0)
        continue;

      bucketFor(bigramBuckets, first).consider(second, count);
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
  loadLetterMap("ngrams/count_2l.txt", 2);
  loadLetterMap("ngrams/count_3l.txt", 3);
}

void loadLetterMap(String path, int ngramLength)
{
  BufferedReader reader = createReader(path);
  String line = null;

  try
  {
    while ((line = reader.readLine()) != null)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String ngram = line.substring(0, tab).trim().toLowerCase();
      if (ngram.length() != ngramLength || !isAlphaWord(ngram))
        continue;

      long count = parseCount(line.substring(tab + 1));
      if (count <= 0)
        continue;

      if (ngramLength == 2)
      {
        String key = "" + ngram.charAt(0);
        char next = ngram.charAt(1);
        charBucketFor(nextLetter1, key).consider(next, logCount(count));
        rememberCommonChunk(ngram, 2);
      }
      else
      {
        String key = ngram.substring(0, 2);
        char next = ngram.charAt(2);
        charBucketFor(nextLetter2, key).consider(next, logCount(count));
        rememberCommonChunk(ngram, 3);
      }
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

void loadEditPatterns()
{
  BufferedReader reader = createReader("ngrams/count_1edit.txt");
  String line = null;

  try
  {
    while ((line = reader.readLine()) != null)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String key = line.substring(0, tab).trim().toLowerCase();
      float count = parseCount(line.substring(tab + 1));
      if (count > 0)
        editWeights.put(key, count);
    }
  }
  catch (Exception e)
  {
    println("Could not load count_1edit.txt");
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void loadDictionary(String path)
{
  BufferedReader reader = createReader(path);
  String line = null;

  try
  {
    while ((line = reader.readLine()) != null)
    {
      String word = line.trim().toLowerCase();
      if (isAlphaWord(word))
        dictionary.add(word);
    }
  }
  catch (Exception e)
  {
    println("Could not load dictionary " + path);
    e.printStackTrace();
  }
  finally
  {
    closeReader(reader);
  }
}

void rememberCommonChunk(String chunk, int chunkLength)
{
  if (chunk == null || chunk.length() != chunkLength)
    return;

  if (chunkLength == 2)
  {
    if (commonBigramCount >= commonBigrams.length)
      return;
    for (int i = 0; i < commonBigramCount; i++)
    {
      if (commonBigrams[i].equals(chunk))
        return;
    }
    commonBigrams[commonBigramCount++] = chunk;
    return;
  }

  if (chunkLength == 3)
  {
    if (commonTrigramCount >= commonTrigrams.length)
      return;
    for (int i = 0; i < commonTrigramCount; i++)
    {
      if (commonTrigrams[i].equals(chunk))
        return;
    }
    commonTrigrams[commonTrigramCount++] = chunk;
  }
}

void addBucketMatches(HashMap<String, Float> scoreMap, WordBucket bucket, String prefix, float multiplier)
{
  if (bucket == null)
    return;

  for (int i = 0; i < bucket.words.length; i++)
  {
    String word = bucket.words[i];
    if (word == null)
      continue;
    if (prefix.length() > 0 && !word.startsWith(prefix))
      continue;
    addScore(scoreMap, word, scoreFromCount(bucket.counts[i], multiplier));
  }
}

void addScore(HashMap<String, Float> scoreMap, String key, float score)
{
  if (key == null || key.length() == 0)
    return;

  float current = scoreMap.containsKey(key) ? scoreMap.get(key) : 0;
  scoreMap.put(key, current + score);
}

void addCharScore(HashMap<Character, Float> scores, char key, float score)
{
  float current = scores.containsKey(key) ? scores.get(key) : 0;
  scores.put(key, current + score);
}

void addCharBucket(HashMap<Character, Float> scores, CharBucket bucket, float multiplier)
{
  if (bucket == null)
    return;

  for (int i = 0; i < bucket.letters.length; i++)
  {
    if (bucket.letters[i] == 0)
      continue;
    addCharScore(scores, bucket.letters[i], bucket.scores[i] * multiplier);
  }
}

ArrayList<ScoredString> sortScoreMap(HashMap<String, Float> scoreMap, int limit)
{
  ArrayList<ScoredString> result = new ArrayList<ScoredString>();
  for (String key : scoreMap.keySet())
    insertSorted(result, new ScoredString(key, scoreMap.get(key)), limit);
  return result;
}

ArrayList<ScoredString> sortCharScoreMap(HashMap<Character, Float> scoreMap, int limit)
{
  ArrayList<ScoredString> result = new ArrayList<ScoredString>();
  for (Character key : scoreMap.keySet())
    insertSorted(result, new ScoredString("" + key.charValue(), scoreMap.get(key)), limit);
  return result;
}

void tryAddHotTile(ArrayList<HotTile> list, HotTile tile)
{
  if (tile == null || tile.isEmpty())
    return;
  if (tilesConflictWithList(list, tile))
    return;
  list.add(tile);
}

boolean tilesConflictWithList(ArrayList<HotTile> list, HotTile tile)
{
  for (int i = 0; i < list.size(); i++)
  {
    if (tilesConflict(list.get(i), tile))
      return true;
  }
  return false;
}

boolean tilesConflict(HotTile first, HotTile second)
{
  if (first == null || second == null)
    return false;

  if (first.kind == HOT_CLUSTER && second.kind == HOT_CLUSTER)
  {
    for (int i = 0; i < first.optionCount; i++)
      for (int j = 0; j < second.optionCount; j++)
        if (first.options[i].equals(second.options[j]))
          return true;
    return false;
  }

  if (first.kind == HOT_CLUSTER)
    return clusterContains(first, second.commitText);
  if (second.kind == HOT_CLUSTER)
    return clusterContains(second, first.commitText);
  return first.commitText.equals(second.commitText);
}

boolean clusterContains(HotTile tile, String value)
{
  if (value == null || value.length() == 0)
    return false;

  for (int i = 0; i < tile.optionCount; i++)
  {
    if (value.equals(tile.options[i]))
      return true;
  }
  return false;
}

void sortHotTilesByScore(ArrayList<HotTile> tiles)
{
  for (int i = 0; i < tiles.size(); i++)
  {
    for (int j = i + 1; j < tiles.size(); j++)
    {
      if (tiles.get(j).score > tiles.get(i).score)
      {
        HotTile swap = tiles.get(i);
        tiles.set(i, tiles.get(j));
        tiles.set(j, swap);
      }
    }
  }
}

void placeHotTiles(ArrayList<HotTile> selected)
{
  clearHotTiles();
  sortHotTilesByScore(selected);

  if (selected.size() == 0)
    return;

  if (selected.size() == 1)
  {
    hotTiles[1] = selected.get(0);
    return;
  }

  if (selected.size() == 2)
  {
    hotTiles[1] = selected.get(0);
    hotTiles[2] = selected.get(1);
    return;
  }

  hotTiles[0] = selected.get(1);
  hotTiles[1] = selected.get(0);
  hotTiles[2] = selected.get(2);
}

void insertSorted(ArrayList<ScoredString> list, ScoredString entry, int limit)
{
  for (int i = 0; i < list.size(); i++)
  {
    if (list.get(i).text.equals(entry.text))
    {
      if (entry.score > list.get(i).score)
        list.set(i, entry);
      trimAndResort(list, limit);
      return;
    }
  }

  list.add(entry);
  trimAndResort(list, limit);
}

void trimAndResort(ArrayList<ScoredString> list, int limit)
{
  for (int i = 0; i < list.size(); i++)
  {
    for (int j = i + 1; j < list.size(); j++)
    {
      if (list.get(j).score > list.get(i).score)
      {
        ScoredString swap = list.get(i);
        list.set(i, list.get(j));
        list.set(j, swap);
      }
    }
  }

  while (list.size() > limit)
    list.remove(list.size() - 1);
}

String currentWordPrefix()
{
  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) == ' ')
    return "";

  int lastSpace = currentTyped.lastIndexOf(' ');
  if (lastSpace < 0)
    return currentTyped;
  return currentTyped.substring(lastSpace + 1);
}

String previousContextWord()
{
  if (currentTyped.length() == 0)
    return "";

  int end = currentTyped.length() - 1;
  while (end >= 0 && currentTyped.charAt(end) == ' ')
    end--;

  if (end < 0)
    return "";

  if (currentTyped.charAt(currentTyped.length() - 1) != ' ')
  {
    while (end >= 0 && currentTyped.charAt(end) != ' ')
      end--;
    while (end >= 0 && currentTyped.charAt(end) == ' ')
      end--;
    if (end < 0)
      return "";
  }

  int start = end;
  while (start >= 0 && currentTyped.charAt(start) != ' ')
    start--;

  return currentTyped.substring(start + 1, end + 1);
}

String suffixOfAlpha(String value, int length)
{
  if (value.length() < length)
    return value;
  return value.substring(value.length() - length);
}

boolean isAlphaWord(String value)
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

long parseCount(String raw)
{
  try
  {
    return Long.parseLong(raw.trim());
  }
  catch (Exception e)
  {
    return 0;
  }
}

float scoreFromCount(long count, float multiplier)
{
  return logCount(count) * multiplier;
}

float logCount(long count)
{
  return log(min((float)count, 2147483647.0) + 1.0);
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

WordBucket bucketFor(HashMap<String, WordBucket> map, String key)
{
  WordBucket bucket = map.get(key);
  if (bucket == null)
  {
    bucket = new WordBucket();
    map.put(key, bucket);
  }
  return bucket;
}

CharBucket charBucketFor(HashMap<String, CharBucket> map, String key)
{
  CharBucket bucket = map.get(key);
  if (bucket == null)
  {
    bucket = new CharBucket();
    map.put(key, bucket);
  }
  return bucket;
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum)
    return;

  if (startTime != 0 && finishTime == 0)
  {
    autocorrectTrailingWordInPlace();
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
  currentTyped = "";
  currentPhrase = phrases[currTrialNum];
  activeGroup = -1;
  activeGroupLetters = "";
  clearWordCluster();
  activeTapAction = ACTION_NONE;
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

class ScoredString
{
  String text;
  float score;

  ScoredString(String textValue, float scoreValue)
  {
    text = textValue;
    score = scoreValue;
  }
}

class HotTile
{
  int kind = HOT_EMPTY;
  String label = "";
  String commitText = "";
  String[] options = new String[WORD_CLUSTER_LIMIT];
  int optionCount = 0;
  float score = 0;

  void setDirect(int newKind, String textValue, float scoreValue)
  {
    kind = newKind;
    label = textValue;
    commitText = textValue;
    optionCount = 0;
    score = scoreValue;
  }

  void setCluster(String[] words, int count, float scoreValue)
  {
    kind = HOT_CLUSTER;
    optionCount = min(count, options.length);
    for (int i = 0; i < optionCount; i++)
      options[i] = words[i];
    label = optionCount > 0 ? words[0] : "";
    commitText = "";
    score = scoreValue;
  }

  boolean isEmpty()
  {
    return kind == HOT_EMPTY || (label.length() == 0 && optionCount == 0);
  }
}

class WordBucket
{
  String[] words = new String[WORD_BUCKET_CAPACITY];
  long[] counts = new long[WORD_BUCKET_CAPACITY];

  void consider(String word, long count)
  {
    if (word == null || word.length() == 0)
      return;

    for (int i = 0; i < words.length; i++)
    {
      if (word.equals(words[i]))
      {
        if (count > counts[i])
          counts[i] = count;
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
}

class CharBucket
{
  char[] letters = new char[CHAR_BUCKET_CAPACITY];
  float[] scores = new float[CHAR_BUCKET_CAPACITY];

  void consider(char letter, float scoreValue)
  {
    for (int i = 0; i < letters.length; i++)
    {
      if (letters[i] == letter)
      {
        if (scoreValue > scores[i])
          scores[i] = scoreValue;
        return;
      }
    }

    for (int i = 0; i < letters.length; i++)
    {
      if (letters[i] == 0 || scoreValue > scores[i])
      {
        shiftDownFrom(i);
        letters[i] = letter;
        scores[i] = scoreValue;
        return;
      }
    }
  }

  void shiftDownFrom(int index)
  {
    for (int i = letters.length - 1; i > index; i--)
    {
      letters[i] = letters[i - 1];
      scores[i] = scores[i - 1];
    }
  }
}
