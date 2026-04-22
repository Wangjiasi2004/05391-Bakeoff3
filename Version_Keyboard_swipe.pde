import java.io.BufferedReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.Random;
import java.util.HashMap;
import java.util.HashSet;
import java.util.ArrayList;

// =====================================================================
// MODEL 2 — Paired-QWERTY path glide (no dwell).
//
// The 1" area is a staggered QWERTY where letters are paired into
// 14 bigger keys:
//     Row 1: qw  er  ty  ui  op          (5 keys)
//     Row 2: as  df  gh  jk  l           (5 keys, 'l' alone)
//     Row 3: zx  cv  bn  m               (4 keys, 'm' alone)
//
// Interaction:
//   - Press down, drag across keys, lift. No dwell.
//   - The PATH (ordered list of keys the finger passed over, duplicates
//     collapsed) is captured as you drag.
//   - Visited keys light up green. Current key is yellow.
//   - Lift -> the path is matched against the dictionary; the top-scored
//     word commits + automatic space.
//
// Scoring of a candidate word W against path P:
//     score =  logFreq(W) * 0.35
//           +  bigramBoost(prev, W) * 0.8
//           +  coverage(W, P) * 8.0         [LCS fraction of W's keys]
//           +  3.0 if W_keys[0]  == P[0]    [start-match bonus]
//           +  3.0 if W_keys[-1] == P[-1]   [end-match bonus]
//           +  lengthSim(W, P) * 4.0        [how close path length is to word length]
//           -  |len(W_keys) - len(P)| * 0.3 [length penalty]
//
// Tiny "del" tile in the bottom-right corner — tap it (press+release
// without tracing through keys) to backspace one character.
// =====================================================================

final int DPIofYourDeviceScreen = 125;

// Do not change the following variables
String[] phrases;
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

final String ALPHABET = "abcdefghijklmnopqrstuvwxyz";

// Paired QWERTY layout. Each row is an array of letter-groups (1 or 2 chars).
final String[][] PAIR_ROWS = {
  {"qw", "er", "ty", "ui", "op"},   // 5 keys
  {"as", "df", "gh", "jk", "l"},    // 5 keys, 'l' alone
  {"zx", "cv", "bn", "m"}           // 4 keys, 'm' alone
};
final float[] ROW_OFFSETS = {0.0, 0.25, 0.75};

final int MAX_UNIGRAM_WORDS = 30000;
final int WORD_BUCKET_CAPACITY = 10;

HashMap<String, Long> wordFreq = new HashMap<String, Long>();
HashMap<String, WordBucket> bigramBuckets = new HashMap<String, WordBucket>();
HashSet<String> dictionary = new HashSet<String>();

// For each word: the sequence of flat-key indices it corresponds to.
// We precompute this so matching is fast.
ArrayList<String> rankedWords = new ArrayList<String>();   // freq-desc
int[][] wordKeys;                                           // wordKeys[i] = key-index array for rankedWords.get(i)

// Flat key index (0..13) -> letter-group string
String[] flatGroups;

// In-progress trace state
ArrayList<Integer> pathKeys = new ArrayList<Integer>();  // collapsed path (no consecutive duplicates)
int currentHoverIndex = -1;
boolean tracing = false;
boolean deleteTapCandidate = false;

// For visualizing the trail, keep a short window of recent mouse positions.
ArrayList<PVector> trail = new ArrayList<PVector>();
final int TRAIL_MAX = 40;

void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());
  buildFlatGroups();
  loadLanguageModel();
  precomputeWordKeys();

  orientation(LANDSCAPE);
  size(800, 800);
  textFont(createFont("Arial", 24));
  noStroke();

  noCursor();
  mouseCursor = loadImage("finger.png");
  cursorHeight = DPIofYourDeviceScreen * (400.0 / 250.0);
  cursorWidth = cursorHeight * 0.6;
}

void buildFlatGroups()
{
  int n = 0;
  for (int r = 0; r < PAIR_ROWS.length; r++) n += PAIR_ROWS[r].length;
  flatGroups = new String[n];
  int idx = 0;
  for (int r = 0; r < PAIR_ROWS.length; r++)
    for (int c = 0; c < PAIR_ROWS[r].length; c++)
      flatGroups[idx++] = PAIR_ROWS[r][c];
}

int keyOf(char c)
{
  for (int k = 0; k < flatGroups.length; k++)
    if (flatGroups[k].indexOf(c) >= 0) return k;
  return -1;
}

// Precompute key-sequence for every word, sorted by freq desc.
void precomputeWordKeys()
{
  ArrayList<String> all = new ArrayList<String>(wordFreq.keySet());
  final HashMap<String, Long> freqRef = wordFreq;
  Collections.sort(all, new java.util.Comparator<String>() {
    public int compare(String a, String b) {
      return Long.compare(freqRef.get(b), freqRef.get(a));
    }
  });
  rankedWords = all;
  wordKeys = new int[all.size()][];
  for (int i = 0; i < all.size(); i++) {
    String w = all.get(i);
    int[] ks = new int[w.length()];
    boolean bad = false;
    for (int j = 0; j < w.length(); j++) {
      int k = keyOf(w.charAt(j));
      if (k < 0) { bad = true; break; }
      ks[j] = k;
    }
    wordKeys[i] = bad ? null : ks;
  }
  println("Precomputed key-seqs for " + rankedWords.size() + " words.");
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
  {
    updatePath();
    drawTrail();
    drawOutsideUI();
  }

  image(mouseCursor, mouseX + cursorWidth / 2 - cursorWidth / 3, mouseY + cursorHeight / 2 - cursorHeight / 5, cursorWidth, cursorHeight);
}

void drawInputArea()
{
  fill(34);
  rect(inputLeft(), inputTop(), sizeOfInputArea, sizeOfInputArea, 18);
  fill(50);
  rect(inputLeft() + 4, inputTop() + 4, sizeOfInputArea - 8, sizeOfInputArea - 8, 15);

  drawKeyboard();
  drawDeleteKey();
}

void drawKeyboard()
{
  textAlign(CENTER, CENTER);
  float kw = keyWidth();
  float kh = keyHeight();

  int flatIdx = 0;
  for (int row = 0; row < PAIR_ROWS.length; row++) {
    String[] rowKeys = PAIR_ROWS[row];
    float rowY = keyboardTop() + row * kh;
    float rowX0 = inputLeft() + keyboardPaddingX() + ROW_OFFSETS[row] * kw;

    for (int col = 0; col < rowKeys.length; col++) {
      String group = rowKeys[col];
      float x = rowX0 + col * kw;
      float y = rowY;

      boolean isHover = tracing && flatIdx == currentHoverIndex;
      boolean isVisited = pathContains(flatIdx);

      if (isHover)
        fill(246, 206, 92);   // yellow: finger is here right now
      else if (isVisited)
        fill(120, 180, 120);  // green: path has been through this key
      else
        fill(108);
      rect(x + 2, y + 2, kw - 4, kh - 4, 7);

      fill(isHover ? color(20) : color(248));
      textSize(letterTextSize(group.length()));
      text(group, x + kw / 2, y + kh / 2 + 1);

      flatIdx++;
    }
  }
}

void drawDeleteKey()
{
  float[] r = deleteRect();
  boolean pressed = deleteTapCandidate;
  fill(pressed ? color(246, 206, 92) : color(178, 90, 90));
  rect(r[0], r[1], r[2], r[3], 6);
  fill(pressed ? color(20) : color(248));
  textAlign(CENTER, CENTER);
  textSize(10);
  text("del", r[0] + r[2] / 2, r[1] + r[3] / 2 + 1);
}

void drawTrail()
{
  if (trail.size() < 2) return;
  // Draw soft trailing line for visual feedback.
  noFill();
  strokeWeight(3);
  stroke(255, 220, 90, 170);
  beginShape();
  for (int i = 0; i < trail.size(); i++) {
    PVector p = trail.get(i);
    vertex(p.x, p.y);
  }
  endShape();
  noStroke();
}

void drawOutsideUI()
{
  textAlign(LEFT, CENTER);
  fill(128);
  textSize(24);
  text("Phrase " + (currTrialNum + 1) + " of " + totalTrialNum, 70, 50);
  text("Target:   " + currentPhrase, 70, 100);

  String preview = currentTyped;
  if (pathKeys.size() > 0) preview += "[" + currentBestGuess() + "]";
  text("Entered:  " + preview + "|", 70, 140);

  fill(255);
  rect(580, 580, 180, 90, 14);
  fill(100);
  textAlign(CENTER, CENTER);
  text("NEXT >", 670, 625);
}

// ---------- Path capture ----------

boolean pathContains(int flatIdx)
{
  for (int i = 0; i < pathKeys.size(); i++)
    if (pathKeys.get(i) == flatIdx) return true;
  return false;
}

void updatePath()
{
  if (!tracing) return;

  // Track the current hover key.
  int idx = keyIndexAt(mouseX, mouseY);
  currentHoverIndex = idx;

  // Append to path only when the finger moves onto a NEW key (collapse dupes).
  if (idx >= 0) {
    int last = pathKeys.size() > 0 ? pathKeys.get(pathKeys.size() - 1) : -1;
    if (idx != last) pathKeys.add(idx);
  }

  // Record the cursor for the trail visual.
  if (trail.size() == 0 || trail.get(trail.size() - 1).dist(new PVector(mouseX, mouseY)) > 3) {
    trail.add(new PVector(mouseX, mouseY));
    while (trail.size() > TRAIL_MAX) trail.remove(0);
  }
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

  // Delete key takes priority over trace start.
  float[] d = deleteRect();
  if (pointInRect(mouseX, mouseY, d[0], d[1], d[2], d[3])) {
    deleteTapCandidate = true;
    return;
  }

  if (!isInsideInput(mouseX, mouseY))
    return;

  // Start a trace: reset path and visuals.
  tracing = true;
  pathKeys.clear();
  trail.clear();
  int idx = keyIndexAt(mouseX, mouseY);
  currentHoverIndex = idx;
  if (idx >= 0) pathKeys.add(idx);
  trail.add(new PVector(mouseX, mouseY));
}

void mouseReleased()
{
  if (deleteTapCandidate) {
    float[] d = deleteRect();
    if (pointInRect(mouseX, mouseY, d[0], d[1], d[2], d[3])) {
      if (currentTyped.length() > 0)
        currentTyped = currentTyped.substring(0, currentTyped.length() - 1);
    }
    deleteTapCandidate = false;
    return;
  }

  if (!tracing) return;

  tracing = false;
  currentHoverIndex = -1;

  if (pathKeys.size() == 0) { trail.clear(); return; }

  // Resolve path to best dictionary word, commit + automatic space.
  String best = currentBestGuess();
  currentTyped += best;
  if (currentTyped.length() == 0 || currentTyped.charAt(currentTyped.length() - 1) != ' ')
    currentTyped += " ";

  pathKeys.clear();
  trail.clear();
}

// ---------- Path -> word scoring ----------

String currentBestGuess()
{
  if (pathKeys.size() == 0) return "";

  int pathLen = pathKeys.size();
  int[] path = new int[pathLen];
  for (int i = 0; i < pathLen; i++) path[i] = pathKeys.get(i);

  // Quick set-membership for coarse prefilter.
  boolean[] inPath = new boolean[flatGroups.length];
  for (int i = 0; i < pathLen; i++) inPath[path[i]] = true;

  String prev = previousContextWord().toLowerCase();

  // Walk freq-desc word list, score candidates.
  float bestScore = -1e9;
  String bestWord = "";

  // Hard special case: path length 1 -> prefer the single-letter word if it exists.
  // (Otherwise e.g. a 1-key path would tend to pick longer words by coverage.)
  for (int i = 0; i < rankedWords.size(); i++) {
    int[] ks = wordKeys[i];
    if (ks == null) continue;

    // Coarse prefilter: every key of the word must exist somewhere in the path.
    // Without this we waste time scoring thousands of irrelevant words.
    boolean ok = true;
    for (int j = 0; j < ks.length; j++) if (!inPath[ks[j]]) { ok = false; break; }
    if (!ok) continue;

    String w = rankedWords.get(i);
    long f = wordFreq.containsKey(w) ? wordFreq.get(w) : 1;
    float s = scoreWordAgainstPath(ks, path, f, prev, w);
    if (s > bestScore) {
      bestScore = s;
      bestWord = w;
    }
  }

  if (bestWord.length() == 0) {
    // Fallback: build a raw word from first-letters-of-each-key on the path.
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < pathLen; i++) sb.append(flatGroups[path[i]].charAt(0));
    return sb.toString();
  }
  return bestWord;
}

float scoreWordAgainstPath(int[] wKeys, int[] path, long freqCount, String prev, String word)
{
  if (wKeys.length == 0 || path.length == 0) return -1e9;

  // LCS of wKeys and path (ordered key coverage).
  int m = wKeys.length, n = path.length;
  // Using 1D rolling array would save memory, but m,n <= ~30 so this is fine.
  int[][] dp = new int[m + 1][n + 1];
  for (int i = 0; i < m; i++)
    for (int j = 0; j < n; j++)
      dp[i + 1][j + 1] = (wKeys[i] == path[j])
        ? dp[i][j] + 1
        : max(dp[i + 1][j], dp[i][j + 1]);
  int lcs = dp[m][n];
  float coverage = lcs / (float) m;

  // Endpoint bonuses (soft — don't require, just reward).
  float startBonus = (wKeys[0] == path[0]) ? 3.0 : 0.0;
  float endBonus   = (wKeys[m - 1] == path[n - 1]) ? 3.0 : 0.0;

  // Length similarity: the path typically has ~= word.length unique keys.
  int uniqKeysInWord = countUniqueKeys(wKeys);
  float lengthSim = (float) min(uniqKeysInWord, n) / (float) max(1, max(uniqKeysInWord, n));

  float logF = log(min((float) freqCount, 2e9f) + 1.0);

  float bigramBoost = 0;
  if (prev != null && prev.length() > 0) {
    WordBucket bb = bigramBuckets.get(prev);
    if (bb != null) {
      for (int k = 0; k < bb.words.length; k++) {
        if (word.equals(bb.words[k])) { bigramBoost = log(bb.counts[k] + 1.0f) * 0.8; break; }
      }
    }
  }

  return logF * 0.35
       + bigramBoost
       + coverage * 8.0
       + startBonus + endBonus
       + lengthSim * 4.0
       - abs(m - n) * 0.3;
}

int countUniqueKeys(int[] ks)
{
  // ks is short; O(n^2) is fine.
  int unique = 0;
  for (int i = 0; i < ks.length; i++) {
    boolean seen = false;
    for (int j = 0; j < i; j++) if (ks[j] == ks[i]) { seen = true; break; }
    if (!seen) unique++;
  }
  return unique;
}

// ---------- Geometry / hit testing ----------

boolean didMouseClick(float x, float y, float w, float h)
{
  return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
}

boolean pointInRect(float px, float py, float x, float y, float w, float h)
{
  return px >= x && px <= x + w && py >= y && py <= y + h;
}

boolean isInsideInput(float x, float y)
{
  return x >= inputLeft() && x <= inputLeft() + sizeOfInputArea && y >= inputTop() && y <= inputTop() + sizeOfInputArea;
}

float inputLeft()    { return width / 2.0 - sizeOfInputArea / 2.0; }
float inputTop()     { return height / 2.0 - sizeOfInputArea / 2.0; }

float keyboardTop()     { return inputTop() + sizeOfInputArea * 0.05; }
float keyboardBottom()  { return inputTop() + sizeOfInputArea * 0.98; }
float keyboardPaddingX(){ return 4; }
float keyWidth()
{
  float usable = sizeOfInputArea - 2 * keyboardPaddingX();
  return usable / 5.25;
}
float keyHeight()
{
  return (keyboardBottom() - keyboardTop()) / 3.0;
}

float letterTextSize(int groupLen)
{
  float base = keyHeight() * 0.45;
  return max(10, groupLen == 2 ? base * 0.95 : base);
}

float[] deleteRect()
{
  float w = sizeOfInputArea * 0.18;
  float h = keyHeight() * 0.80;
  float x = inputLeft() + sizeOfInputArea - w - 4;
  float y = keyboardTop() + 2 * keyHeight() + (keyHeight() - h) / 2.0;
  return new float[] {x, y, w, h};
}

int keyIndexAt(float x, float y)
{
  float[] d = deleteRect();
  if (pointInRect(x, y, d[0], d[1], d[2], d[3])) return -1;

  if (y < keyboardTop() || y >= keyboardBottom()) return -1;

  float kh = keyHeight();
  int row = (int)((y - keyboardTop()) / kh);
  if (row < 0 || row >= PAIR_ROWS.length) return -1;

  float kw = keyWidth();
  float rowX0 = inputLeft() + keyboardPaddingX() + ROW_OFFSETS[row] * kw;
  String[] rowKeys = PAIR_ROWS[row];

  int col = (int)((x - rowX0) / kw);
  if (col < 0 || col >= rowKeys.length) return -1;

  int flat = 0;
  for (int r = 0; r < row; r++) flat += PAIR_ROWS[r].length;
  return flat + col;
}

// ---------- Language model loading ----------

void loadLanguageModel()
{
  loadWords();
  loadBigrams();
  loadDictionary("ngrams/enable1.txt");
  loadDictionary("ngrams/TWL06.txt");
}

void loadWords()
{
  BufferedReader reader = createReader("ngrams/count_1w.txt");
  String line = null;
  int loaded = 0;

  try
  {
    while ((line = reader.readLine()) != null && loaded < MAX_UNIGRAM_WORDS)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0) continue;

      String word = line.substring(0, tab).trim().toLowerCase();
      if (!isAlphaWord(word)) continue;

      long count = parseCount(line.substring(tab + 1));
      if (count <= 0) continue;

      wordFreq.put(word, count);
      loaded++;
    }
  }
  catch (Exception e) { println("Could not load count_1w.txt"); e.printStackTrace(); }
  finally { closeReader(reader); }
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
      if (tab <= 0) continue;

      String pair = line.substring(0, tab).trim().toLowerCase();
      int spaceIndex = pair.indexOf(' ');
      if (spaceIndex <= 0 || spaceIndex >= pair.length() - 1) continue;
      if (pair.indexOf(' ', spaceIndex + 1) != -1) continue;

      String first = pair.substring(0, spaceIndex);
      String second = pair.substring(spaceIndex + 1);
      if (!isAlphaWord(first) || !isAlphaWord(second)) continue;

      long count = parseCount(line.substring(tab + 1));
      if (count <= 0) continue;

      bucketFor(bigramBuckets, first).consider(second, count);
    }
  }
  catch (Exception e) { println("Could not load count_2w.txt"); e.printStackTrace(); }
  finally { closeReader(reader); }
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
      if (isAlphaWord(word)) dictionary.add(word);
    }
  }
  catch (Exception e) { println("Could not load dictionary " + path); e.printStackTrace(); }
  finally { closeReader(reader); }
}

// ---------- Helpers ----------

String previousContextWord()
{
  if (currentTyped.length() == 0) return "";

  int end = currentTyped.length() - 1;
  while (end >= 0 && currentTyped.charAt(end) == ' ') end--;
  if (end < 0) return "";

  int start = end;
  while (start >= 0 && currentTyped.charAt(start) != ' ') start--;
  return currentTyped.substring(start + 1, end + 1);
}

boolean isAlphaWord(String value)
{
  if (value == null || value.length() == 0) return false;
  for (int i = 0; i < value.length(); i++) {
    char c = value.charAt(i);
    if (c < 'a' || c > 'z') return false;
  }
  return true;
}

long parseCount(String raw)
{
  try { return Long.parseLong(raw.trim()); }
  catch (Exception e) { return 0; }
}

void closeReader(BufferedReader reader)
{
  try { if (reader != null) reader.close(); } catch (Exception e) {}
}

WordBucket bucketFor(HashMap<String, WordBucket> map, String key)
{
  WordBucket bucket = map.get(key);
  if (bucket == null) { bucket = new WordBucket(); map.put(key, bucket); }
  return bucket;
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum)
    return;

  if (startTime != 0 && finishTime == 0)
  {
    if (pathKeys.size() > 0) {
      currentTyped += currentBestGuess();
      pathKeys.clear();
      trail.clear();
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
  pathKeys.clear();
  trail.clear();
  tracing = false;
  currentHoverIndex = -1;
  deleteTapCandidate = false;
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

  for (int i = 0; i <= phrase1.length(); i++) distance[i][0] = i;
  for (int j = 1; j <= phrase2.length(); j++) distance[0][j] = j;

  for (int i = 1; i <= phrase1.length(); i++)
    for (int j = 1; j <= phrase2.length(); j++)
      distance[i][j] = min(min(distance[i - 1][j] + 1, distance[i][j - 1] + 1), distance[i - 1][j - 1] + ((phrase1.charAt(i - 1) == phrase2.charAt(j - 1)) ? 0 : 1));

  return distance[phrase1.length()][phrase2.length()];
}

// ---------- Data classes ----------

class WordBucket
{
  String[] words = new String[WORD_BUCKET_CAPACITY];
  long[] counts = new long[WORD_BUCKET_CAPACITY];

  void consider(String word, long count)
  {
    if (word == null || word.length() == 0) return;

    for (int i = 0; i < words.length; i++) {
      if (word.equals(words[i])) { if (count > counts[i]) counts[i] = count; return; }
    }
    for (int i = 0; i < words.length; i++) {
      if (words[i] == null || count > counts[i]) {
        shiftDownFrom(i);
        words[i] = word;
        counts[i] = count;
        return;
      }
    }
  }

  void shiftDownFrom(int index)
  {
    for (int i = words.length - 1; i > index; i--) {
      words[i] = words[i - 1];
      counts[i] = counts[i - 1];
    }
  }
}
