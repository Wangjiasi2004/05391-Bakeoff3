import java.util.Arrays;
import java.util.Collections;
import java.util.Random;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

// =================================================================
// PROTOTYPE 2 — Ambiguous (T9-style) 6-group keyboard + expanded
// dynamic autocomplete.
//
// Inside the 1" area:
//   [ sugg1 ][ sugg2 ][ sugg3 ]   <- 3 autocomplete chips
//   [ abcd ][ efgh ][ ijklm  ]
//   [ nopqr][ stuv ][ wxyz   ]
//   [ space         ][ del    ]
//
// One tap per letter (group key). Suggestions are computed by
// matching the group sequence against a dictionary, ranked by
// unigram frequency. When no letters have been typed yet in the
// new word, suggestions are seeded by bigram context (most-likely
// next word after the last committed word).
//
// A "raw" chip (literal first-letter-of-each-group the user typed)
// is always available in the chip row so the user can type words
// not in the dictionary.
// =================================================================

// Set the DPI to make your smartwatch 1 inch square.
final int DPIofYourDeviceScreen = 250;

//Do not change the following variables
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
final float sizeOfInputArea = DPIofYourDeviceScreen*1;
PImage watch;
PImage mouseCursor;
float cursorHeight;
float cursorWidth;

// ----- Prototype state -----
ArrayList<Integer> groupSeq = new ArrayList<Integer>();
String lastCommittedWord = "";
String[] currentSuggestions = new String[3];

// Dictionaries
HashMap<String, Long> unigramFreq;
ArrayList<String> unigramSorted;
HashMap<String, ArrayList<String>> bigramNext;
// Map: group-code string ("3-0-4") -> freq-desc list of matching words
HashMap<String, ArrayList<String>> groupLookup;

// Letter groups (6 groups cover a-z)
final String[] GROUPS = {"abcd", "efgh", "ijklm", "nopqr", "stuv", "wxyz"};

// Fonts
PFont fontKey;
PFont fontSuggest;
PFont fontUI;

// Layout
float inputLeft, inputTop;
float suggH, letterH, bottomH;

// Flash feedback
long lastKeyFlashTime = 0;
int lastKeyFlashed = -1;
int lastSpecialFlash = 0; // 1 = space, 2 = del

void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());

  orientation(LANDSCAPE);
  size(800, 800);

  fontKey = createFont("Arial Bold", 18);
  fontSuggest = createFont("Arial", 15);
  fontUI = createFont("Arial", 24);
  textFont(fontUI);
  noStroke();

  noCursor();
  mouseCursor = loadImage("finger.png");
  cursorHeight = DPIofYourDeviceScreen * (400.0/250.0);
  cursorWidth = cursorHeight * 0.6;

  inputLeft = width/2 - sizeOfInputArea/2;
  inputTop  = height/2 - sizeOfInputArea/2;
  suggH   = sizeOfInputArea * 0.22;
  letterH = sizeOfInputArea * 0.29;
  bottomH = sizeOfInputArea - suggH - 2*letterH;

  loadDictionaries();
  buildGroupLookup();
  updateSuggestions();
}

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

void loadDictionaries()
{
  unigramFreq = new HashMap<String, Long>();
  unigramSorted = new ArrayList<String>();
  bigramNext = new HashMap<String, ArrayList<String>>();

  String[] uni = loadStrings("uni_small.txt");
  for (int i = 0; i < uni.length; i++) {
    String[] parts = uni[i].split("\t");
    if (parts.length < 2) continue;
    String w = parts[0];
    long c;
    try { c = Long.parseLong(parts[1]); } catch (Exception e) { continue; }
    unigramFreq.put(w, c);
    unigramSorted.add(w);
  }

  String[] bi = loadStrings("bi_small.txt");
  for (int i = 0; i < bi.length; i++) {
    String[] parts = bi[i].split("\t");
    if (parts.length < 3) continue;
    String a = parts[0], b = parts[1];
    ArrayList<String> lst = bigramNext.get(a);
    if (lst == null) { lst = new ArrayList<String>(); bigramNext.put(a, lst); }
    lst.add(b);
  }
  println("Loaded " + unigramFreq.size() + " unigrams, " + bigramNext.size() + " bigram heads.");
}

void buildGroupLookup()
{
  groupLookup = new HashMap<String, ArrayList<String>>();
  for (String w : unigramSorted) {
    String code = wordToGroupCode(w);
    if (code == null) continue;
    ArrayList<String> lst = groupLookup.get(code);
    if (lst == null) { lst = new ArrayList<String>(); groupLookup.put(code, lst); }
    lst.add(w);
  }
  println("Built group lookup with " + groupLookup.size() + " buckets.");
}

String currentCode()
{
  StringBuilder sb = new StringBuilder();
  for (int i = 0; i < groupSeq.size(); i++) {
    if (i > 0) sb.append('-');
    sb.append(groupSeq.get(i));
  }
  return sb.toString();
}

// Literal fallback: first letter of each group the user tapped.
String rawFirstLetters()
{
  StringBuilder sb = new StringBuilder();
  for (int g : groupSeq) sb.append(GROUPS[g].charAt(0));
  return sb.toString();
}

void updateSuggestions()
{
  ArrayList<String> picks = new ArrayList<String>();

  if (groupSeq.size() == 0) {
    // Seed from bigrams following lastCommittedWord
    if (lastCommittedWord.length() > 0 && bigramNext.containsKey(lastCommittedWord)) {
      for (String w : bigramNext.get(lastCommittedWord)) {
        if (picks.size() >= 3) break;
        picks.add(w);
      }
    }
    for (int i = 0; i < unigramSorted.size() && picks.size() < 3; i++) {
      String w = unigramSorted.get(i);
      if (!picks.contains(w)) picks.add(w);
    }
  } else {
    // Exact length matches first
    String code = currentCode();
    ArrayList<String> exact = groupLookup.get(code);
    if (exact != null) {
      for (int i = 0; i < exact.size() && picks.size() < 3; i++) picks.add(exact.get(i));
    }
    // Then longer prefix matches (completion)
    if (picks.size() < 3) {
      String pref = code + "-";
      for (int i = 0; i < unigramSorted.size() && picks.size() < 3; i++) {
        String w = unigramSorted.get(i);
        if (w.length() <= groupSeq.size()) continue;
        String c2 = wordToGroupCode(w);
        if (c2 != null && c2.startsWith(pref) && !picks.contains(w)) picks.add(w);
      }
    }
    // Always guarantee a raw fallback is on screen
    String raw = rawFirstLetters();
    if (!picks.contains(raw)) {
      if (picks.size() < 3) picks.add(raw);
      else picks.set(2, raw);
    }
  }

  for (int i = 0; i < 3; i++)
    currentSuggestions[i] = (i < picks.size()) ? picks.get(i) : "";
}

void draw()
{
  background(255);
  drawWatch();

  fill(40);
  rect(inputLeft, inputTop, sizeOfInputArea, sizeOfInputArea);

  if (finishTime != 0) {
    fill(128);
    textFont(fontUI);
    textAlign(CENTER);
    text("Finished", 280, 150);
    cursor(ARROW);
    return;
  }

  if (startTime == 0 & !mousePressed) {
    fill(128);
    textFont(fontUI);
    textAlign(CENTER);
    text("Click to start time!", 280, 150);
  }
  if (startTime == 0 & mousePressed) {
    nextTrial();
  }

  if (startTime != 0) {
    textFont(fontUI);
    textAlign(LEFT);
    fill(128);
    text("Phrase " + (currTrialNum+1) + " of " + totalTrialNum, 70, 50);
    text("Target:   " + currentPhrase, 70, 100);
    String preview = currentTyped;
    if (groupSeq.size() > 0) preview += "[" + rawFirstLetters() + "]";
    text("Entered:  " + preview + "|", 70, 140);

    // NEXT button (kept white/plain per rules)
    fill(255);
    rect(600, 600, 200, 200);
    fill(0);
    textAlign(CENTER);
    text("NEXT >", 700, 710);

    drawKeyboard();
  }

  image(mouseCursor, mouseX+cursorWidth/2-cursorWidth/3, mouseY+cursorHeight/2-cursorHeight/5, cursorWidth, cursorHeight);
}

void drawKeyboard()
{
  // Suggestion chips
  float sx = inputLeft;
  float sy = inputTop;
  float sw = sizeOfInputArea / 3.0;
  textFont(fontSuggest);
  textAlign(CENTER, CENTER);
  for (int i = 0; i < 3; i++) {
    fill(70, 130, 180);
    rect(sx + i*sw + 1, sy + 1, sw - 2, suggH - 2, 5);
    fill(255);
    String s = currentSuggestions[i];
    if (s != null && s.length() > 10) s = s.substring(0, 10);
    text(s == null ? "" : s, sx + i*sw + sw/2, sy + suggH/2);
  }

  // Letter-group keys (2 rows of 3)
  textFont(fontKey);
  float kW = sizeOfInputArea / 3.0;
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 3; c++) {
      int idx = r*3 + c;
      float x = inputLeft + c*kW;
      float y = inputTop + suggH + r*letterH;
      boolean flash = (idx == lastKeyFlashed) && (millis() - lastKeyFlashTime < 120);
      fill(flash ? color(255, 220, 90) : 245);
      rect(x + 1, y + 1, kW - 2, letterH - 2, 5);
      fill(20);
      text(GROUPS[idx], x + kW/2, y + letterH/2);
    }
  }

  // Bottom row: space (2/3) + delete (1/3)
  float by = inputTop + suggH + 2*letterH;
  float spaceW = sizeOfInputArea * (2.0/3.0);
  float delW = sizeOfInputArea - spaceW;
  boolean flashSpace = (lastSpecialFlash == 1) && (millis() - lastKeyFlashTime < 120);
  boolean flashDel   = (lastSpecialFlash == 2) && (millis() - lastKeyFlashTime < 120);
  fill(flashSpace ? color(255, 220, 90) : 210);
  rect(inputLeft + 1, by + 1, spaceW - 2, bottomH - 2, 5);
  fill(30);
  textFont(fontSuggest);
  textAlign(CENTER, CENTER);
  text("space", inputLeft + spaceW/2, by + bottomH/2);

  fill(flashDel ? color(255, 220, 90) : color(180, 60, 60));
  rect(inputLeft + spaceW + 1, by + 1, delW - 2, bottomH - 2, 5);
  fill(255);
  text("del", inputLeft + spaceW + delW/2, by + bottomH/2);
}

boolean didMouseClick(float x, float y, float w, float h)
{
  return (mouseX > x && mouseX<x+w && mouseY>y && mouseY<y+h);
}

void mousePressed()
{
  if (finishTime != 0) return;

  // NEXT (outside 1" area)
  if (didMouseClick(600, 600, 200, 200)) { nextTrial(); return; }

  if (startTime == 0) return;

  // Suggestion chips
  float sx = inputLeft, sy = inputTop;
  float sw = sizeOfInputArea / 3.0;
  for (int i = 0; i < 3; i++) {
    if (didMouseClick(sx + i*sw, sy, sw, suggH)) {
      String pick = currentSuggestions[i];
      if (pick != null && pick.length() > 0) {
        currentTyped += pick + " ";
        lastCommittedWord = pick;
        groupSeq.clear();
        updateSuggestions();
      }
      return;
    }
  }

  // Letter-group keys
  float kW = sizeOfInputArea / 3.0;
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 3; c++) {
      int idx = r*3 + c;
      float x = inputLeft + c*kW;
      float y = inputTop + suggH + r*letterH;
      if (didMouseClick(x, y, kW, letterH)) {
        groupSeq.add(idx);
        lastKeyFlashed = idx;
        lastSpecialFlash = 0;
        lastKeyFlashTime = millis();
        updateSuggestions();
        return;
      }
    }
  }

  // Space / delete
  float by = inputTop + suggH + 2*letterH;
  float spaceW = sizeOfInputArea * (2.0/3.0);
  float delW = sizeOfInputArea - spaceW;
  if (didMouseClick(inputLeft, by, spaceW, bottomH)) {
    // Space: commit top suggestion if we're mid-word; else insert a space.
    if (groupSeq.size() > 0) {
      String commit = (currentSuggestions[0] != null && currentSuggestions[0].length() > 0)
                        ? currentSuggestions[0]
                        : rawFirstLetters();
      currentTyped += commit + " ";
      lastCommittedWord = commit;
      groupSeq.clear();
    } else {
      currentTyped += " ";
      lastCommittedWord = "";
    }
    lastSpecialFlash = 1;
    lastKeyFlashed = -1;
    lastKeyFlashTime = millis();
    updateSuggestions();
    return;
  }
  if (didMouseClick(inputLeft + spaceW, by, delW, bottomH)) {
    if (groupSeq.size() > 0) {
      groupSeq.remove(groupSeq.size() - 1);
    } else if (currentTyped.length() > 0) {
      currentTyped = currentTyped.substring(0, currentTyped.length()-1);
      String trimmed = currentTyped.trim();
      int sp = trimmed.lastIndexOf(' ');
      lastCommittedWord = (sp >= 0) ? trimmed.substring(sp+1) : trimmed;
    }
    lastSpecialFlash = 2;
    lastKeyFlashed = -1;
    lastKeyFlashTime = millis();
    updateSuggestions();
    return;
  }
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum) return;

  if (startTime!=0 && finishTime==0)
  {
    // Flush any in-progress word so we don't lose taps on trial boundary.
    String finalTyped = currentTyped;
    if (groupSeq.size() > 0) {
      String commit = (currentSuggestions[0] != null && currentSuggestions[0].length() > 0)
                        ? currentSuggestions[0] : rawFirstLetters();
      finalTyped += commit;
    }
    System.out.println("==================");
    System.out.println("Phrase " + (currTrialNum+1) + " of " + totalTrialNum);
    System.out.println("Target phrase: " + currentPhrase);
    System.out.println("Phrase length: " + currentPhrase.length());
    System.out.println("User typed: " + finalTyped);
    System.out.println("User typed length: " + finalTyped.length());
    System.out.println("Number of errors: " + computeLevenshteinDistance(finalTyped.trim(), currentPhrase.trim()));
    System.out.println("Time taken on this trial: " + (millis()-lastTime));
    System.out.println("Time taken since beginning: " + (millis()-startTime));
    System.out.println("==================");
    lettersExpectedTotal += currentPhrase.trim().length();
    lettersEnteredTotal  += finalTyped.trim().length();
    errorsTotal += computeLevenshteinDistance(finalTyped.trim(), currentPhrase.trim());
  }

  if (currTrialNum == totalTrialNum-1)
  {
    finishTime = millis();
    System.out.println("==================");
    System.out.println("Trials complete!");
    System.out.println("Total time taken: " + (finishTime - startTime));
    System.out.println("Total letters entered: " + lettersEnteredTotal);
    System.out.println("Total letters expected: " + lettersExpectedTotal);
    System.out.println("Total errors entered: " + errorsTotal);

    float wpm = (lettersEnteredTotal/5.0f)/((finishTime - startTime)/60000f);
    float freebieErrors = lettersExpectedTotal*.05;
    float penalty = max(errorsTotal-freebieErrors, 0) * .5f;

    System.out.println("Raw WPM: " + wpm);
    System.out.println("Freebie errors: " + freebieErrors);
    System.out.println("Penalty: " + penalty);
    System.out.println("WPM w/ penalty: " + (wpm-penalty));
    System.out.println("==================");
    currTrialNum++;
    return;
  }

  if (startTime == 0) {
    System.out.println("Trials beginning! Starting timer...");
    startTime = millis();
  } else {
    currTrialNum++;
  }

  lastTime = millis();
  currentTyped = "";
  groupSeq.clear();
  lastCommittedWord = "";
  updateSuggestions();
  currentPhrase = phrases[currTrialNum];
}

void drawWatch()
{
  float watchscale = DPIofYourDeviceScreen/138.0;
  pushMatrix();
  translate(width/2, height/2);
  scale(watchscale);
  imageMode(CENTER);
  image(watch, 0, 0);
  popMatrix();
}

//=========SHOULD NOT NEED TO TOUCH THIS METHOD AT ALL!==============
int computeLevenshteinDistance(String phrase1, String phrase2)
{
  int[][] distance = new int[phrase1.length() + 1][phrase2.length() + 1];
  for (int i = 0; i <= phrase1.length(); i++) distance[i][0] = i;
  for (int j = 1; j <= phrase2.length(); j++) distance[0][j] = j;
  for (int i = 1; i <= phrase1.length(); i++)
    for (int j = 1; j <= phrase2.length(); j++)
      distance[i][j] = min(min(distance[i - 1][j] + 1, distance[i][j - 1] + 1),
                           distance[i - 1][j - 1] + ((phrase1.charAt(i - 1) == phrase2.charAt(j - 1)) ? 0 : 1));
  return distance[phrase1.length()][phrase2.length()];
}
