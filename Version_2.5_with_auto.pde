import java.io.BufferedReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.Random;
import java.util.HashMap;
import java.util.HashSet;
import java.util.ArrayList;

// =====================================================================
// MODEL 1 — Group-tap, space-to-resolve.
//
// Each of the 8 letter-group keys records a GROUP TAP (not a drag).
// While the user taps groups, "Entered:" shows a bracketed preview of
// the best-guess word so far: "hello world [wo]".
// Hot tiles in the top strip show candidate words that match the
// tapped-group sequence, ranked by language model. Tapping a hot tile
// commits that word. Tapping SPACE commits the top candidate and
// inserts a space.
// Delete removes ONE LETTER (last character of the committed text).
// There is no letter-selection overlay.
// =====================================================================

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
final int HOT_WORD = 3;

final int PREFIX_LIMIT = 10;
final int MAX_UNIGRAM_WORDS = 70000;
final int WORD_BUCKET_CAPACITY = 10;
final int FALLBACK_WORD_COUNT = 12;

HashMap<String, Long> wordFreq = new HashMap<String, Long>();
HashMap<String, WordBucket> prefixBuckets = new HashMap<String, WordBucket>();
HashMap<String, WordBucket> bigramBuckets = new HashMap<String, WordBucket>();
HashMap<String, Float> editWeights = new HashMap<String, Float>();
HashSet<String> dictionary = new HashSet<String>();

// GroupCode -> candidate words, ranked by freq desc
HashMap<String, ArrayList<String>> groupLookup = new HashMap<String, ArrayList<String>>();

String[] fallbackWords = new String[FALLBACK_WORD_COUNT];

HotTile[] hotTiles = new HotTile[HOT_TILE_COUNT];

// Sequence of tapped group indices (0..7) for the word in progress
ArrayList<Integer> groupSeq = new ArrayList<Integer>();
int activeTapAction = ACTION_NONE;

void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());
  initHotTiles();
  loadLanguageModel();
  buildGroupLookup();

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

  fill(isPressed ? color(20) : color(248));
  textSize(tile.kind == HOT_WORD ? 9 : 12);
  text(drawLabel(tile.label, 8), x + w / 2, y + h / 2 + 1);
}

void drawOutsideUI()
{
  textAlign(LEFT, CENTER);
  fill(128);
  textSize(24);
  text("Phrase " + (currTrialNum + 1) + " of " + totalTrialNum, 70, 50);
  text("Target:   " + currentPhrase, 70, 100);

  // Show the best-guess word for the in-progress group sequence in brackets.
  String preview = currentTyped;
  if (groupSeq.size() > 0)
    preview += "[" + currentBestGuess() + "]";
  text("Entered:  " + preview + "|", 70, 140);

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

  activeTapAction = actionAt(mouseX, mouseY);
}

void mouseReleased()
{
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
    // Delete one LETTER at a time (per user spec).
    if (groupSeq.size() > 0)
    {
      // If there's an in-progress group sequence, drop its last group tap.
      groupSeq.remove(groupSeq.size() - 1);
      return;
    }
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
    int g = action - ACTION_GROUP_BASE;
    groupSeq.add(g);
    return;
  }
}

void applyHotTile(int tileIndex)
{
  HotTile tile = hotTiles[tileIndex];
  if (tile.kind == HOT_EMPTY)
    return;

  if (tile.kind == HOT_WORD)
  {
    applyPredictedWord(tile.commitText);
    return;
  }
}

void applyPredictedWord(String word)
{
  if (word == null || word.length() == 0)
    return;

  // Picking a hot-tile word ends the current group sequence AND commits the
  // word (with trailing space). Behaves like a smarter space-bar.
  groupSeq.clear();
  currentTyped += word;
  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) != ' ')
    currentTyped += " ";
}

void commitWordBoundary()
{
  // If there's a group sequence in progress, resolve it to a word via the
  // T9-style dictionary lookup and commit.
  if (groupSeq.size() > 0)
  {
    String best = currentBestGuess();
    currentTyped += best;
    groupSeq.clear();
  }

  // Always add the space (even if the user just pressed space twice).
  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) != ' ')
    currentTyped += " ";
  else
    currentTyped += " ";
}

// ------------------ Group-sequence disambiguation ------------------

int groupOf(char c)
{
  for (int i = 0; i < GROUPS.length; i++)
    if (GROUPS[i].indexOf(c) >= 0) return i;
  return -1;
}

String wordToGroupCode(String w)
{
  StringBuilder sb = new StringBuilder();
  for (int i = 0; i < w.length(); i++) {
    int g = groupOf(w.charAt(i));
    if (g < 0) return null;
    if (i > 0) sb.append('-');
    sb.append(g);
  }
  return sb.toString();
}

String currentGroupCode()
{
  StringBuilder sb = new StringBuilder();
  for (int i = 0; i < groupSeq.size(); i++) {
    if (i > 0) sb.append('-');
    sb.append(groupSeq.get(i));
  }
  return sb.toString();
}

// Fallback word: first letter of each group the user tapped.
String rawFirstLetters()
{
  StringBuilder sb = new StringBuilder();
  for (int g : groupSeq) sb.append(GROUPS[g].charAt(0));
  return sb.toString();
}

// Build code->words lookup, bucketing all known words by their group code
// (sorted by freq desc inside each bucket).
void buildGroupLookup()
{
  // Sort words by frequency desc once, then bucket.
  ArrayList<String> allWords = new ArrayList<String>(wordFreq.keySet());
  final HashMap<String, Long> freqRef = wordFreq;
  Collections.sort(allWords, new java.util.Comparator<String>() {
    public int compare(String a, String b) {
      long fa = freqRef.containsKey(a) ? freqRef.get(a) : 0;
      long fb = freqRef.containsKey(b) ? freqRef.get(b) : 0;
      return Long.compare(fb, fa);
    }
  });

  for (String w : allWords) {
    String code = wordToGroupCode(w);
    if (code == null) continue;
    ArrayList<String> lst = groupLookup.get(code);
    if (lst == null) { lst = new ArrayList<String>(); groupLookup.put(code, lst); }
    lst.add(w);
  }
  println("Built group lookup with " + groupLookup.size() + " buckets from " + allWords.size() + " words.");
}

// Best-guess word for the current group sequence, biased by bigram context.
String currentBestGuess()
{
  ArrayList<String> picks = candidateWordsForGroupSeq(1);
  if (picks.size() > 0) return picks.get(0);
  return rawFirstLetters();
}

// Produce up to `limit` candidate words for the current group sequence,
// ranked by (bigram-context-boost * unigram frequency). Always includes
// a raw-first-letter fallback as the tail.
ArrayList<String> candidateWordsForGroupSeq(int limit)
{
  ArrayList<String> out = new ArrayList<String>();
  if (groupSeq.size() == 0) return out;

  String code = currentGroupCode();
  ArrayList<String> exact = groupLookup.get(code);
  String prev = previousContextWord().toLowerCase();

  HashMap<String, Float> scores = new HashMap<String, Float>();

  if (exact != null) {
    for (String w : exact) {
      long f = wordFreq.containsKey(w) ? wordFreq.get(w) : 1;
      float s = logCount(f);
      // Bigram boost: if this word commonly follows `prev`, bump it.
      if (prev.length() > 0) {
        WordBucket bb = bigramBuckets.get(prev);
        if (bb != null) {
          for (int i = 0; i < bb.words.length; i++) {
            if (w.equals(bb.words[i])) { s += logCount(bb.counts[i]) * 0.8; break; }
          }
        }
      }
      scores.put(w, s);
    }
  }

  // Rank
  ArrayList<String> ranked = new ArrayList<String>(scores.keySet());
  final HashMap<String, Float> ref = scores;
  Collections.sort(ranked, new java.util.Comparator<String>() {
    public int compare(String a, String b) {
      return Float.compare(ref.get(b), ref.get(a));
    }
  });

  for (int i = 0; i < ranked.size() && out.size() < limit; i++) out.add(ranked.get(i));

  // Raw fallback is ALWAYS available somewhere
  String raw = rawFirstLetters();
  if (!out.contains(raw)) {
    if (out.size() < limit) out.add(raw);
    else if (limit >= 3) out.set(limit - 1, raw);
  }

  return out;
}

// ------------------ Hot tile population ------------------

void refreshHotTiles()
{
  clearHotTiles();

  if (groupSeq.size() > 0)
  {
    // Top-3 word candidates matching current group sequence.
    ArrayList<String> picks = candidateWordsForGroupSeq(3);
    for (int i = 0; i < picks.size() && i < HOT_TILE_COUNT; i++) {
      HotTile t = new HotTile();
      t.setDirect(HOT_WORD, picks.get(i), 1.0f * (3 - i));
      hotTiles[i] = t;
    }
    return;
  }

  // No group sequence yet — show bigram-suggested next words based on
  // the last committed word (dynamic default suggestions).
  String prev = previousContextWord().toLowerCase();
  ArrayList<String> picks = new ArrayList<String>();
  if (prev.length() > 0) {
    WordBucket bb = bigramBuckets.get(prev);
    if (bb != null) {
      for (int i = 0; i < bb.words.length && picks.size() < HOT_TILE_COUNT; i++)
        if (bb.words[i] != null) picks.add(bb.words[i]);
    }
  }
  // Pad with most-frequent words
  for (int i = 0; i < fallbackWords.length && picks.size() < HOT_TILE_COUNT; i++) {
    if (fallbackWords[i] != null && !picks.contains(fallbackWords[i]))
      picks.add(fallbackWords[i]);
  }
  for (int i = 0; i < picks.size() && i < HOT_TILE_COUNT; i++) {
    HotTile t = new HotTile();
    t.setDirect(HOT_WORD, picks.get(i), 1.0f * (3 - i));
    hotTiles[i] = t;
  }
}

// ------------------ Hit testing ------------------

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
    return color(88, 116, 132);
  return color(90);
}

boolean isInsideInput(float x, float y)
{
  return x >= inputLeft() && x <= inputLeft() + sizeOfInputArea && y >= inputTop() && y <= inputTop() + sizeOfInputArea;
}

float inputLeft()     { return width / 2.0 - sizeOfInputArea / 2.0; }
float inputTop()      { return height / 2.0 - sizeOfInputArea / 2.0; }
float inputCenterX()  { return width / 2.0; }
float topStripHeight(){ return sizeOfInputArea * 0.22; }
float topTileWidth()  { return sizeOfInputArea / 4.0; }
float topTileLeft(int index) { return inputLeft() + index * topTileWidth(); }
float keyboardTop()   { return inputTop() + topStripHeight(); }
float keyboardCellWidth(){ return sizeOfInputArea / 3.0; }
float keyboardCellHeight(){ return (sizeOfInputArea - topStripHeight()) / 3.0; }
float keyboardCellLeft(int col){ return inputLeft() + col * keyboardCellWidth(); }
float keyboardCellTop(int row){ return keyboardTop() + row * keyboardCellHeight(); }
float buttonInset()   { return 3; }

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

float previewBoxWidth(int groupLength, float keyWidth)
{
  return groupLength == 4 ? keyWidth * 0.28 : keyWidth * 0.32;
}

float previewBoxHeight(int groupLength, float keyHeight)
{
  return groupLength == 4 ? keyHeight * 0.24 : keyHeight * 0.26;
}

String drawLabel(String label, int maxChars)
{
  if (label == null || label.length() == 0)
    return " ";
  if (label.length() <= maxChars)
    return label;
  return label.substring(0, maxChars);
}

// ------------------ Hot tile plumbing ------------------

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

// ------------------ Language model loading (unchanged structure) ------------------

void loadLanguageModel()
{
  loadWordsAndPrefixes();
  loadBigrams();
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

// ------------------ Helpers ------------------

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

  int start = end;
  while (start >= 0 && currentTyped.charAt(start) != ' ')
    start--;

  return currentTyped.substring(start + 1, end + 1);
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

void nextTrial()
{
  if (currTrialNum >= totalTrialNum)
    return;

  if (startTime != 0 && finishTime == 0)
  {
    // Flush any in-progress group sequence so the user doesn't lose taps.
    if (groupSeq.size() > 0) {
      currentTyped += currentBestGuess();
      groupSeq.clear();
    }
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
  groupSeq.clear();
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

// ------------------ Data classes ------------------

class HotTile
{
  int kind = HOT_EMPTY;
  String label = "";
  String commitText = "";
  String[] options = new String[4];
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
