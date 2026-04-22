import java.io.BufferedReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Random;

// Set the DPI to make your smartwatch 1 inch square. Measure it on the screen
final int DPIofYourDeviceScreen = 125; 

//Do not change the following variables
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
final float sizeOfInputArea = DPIofYourDeviceScreen*1; 
PImage watch;
PImage mouseCursor;
float cursorHeight;
float cursorWidth;

// QWERTY-mapped groups: 3 rows × 3 cols = 9 groups
final String[] GROUPS = {
  "qwe",   // group 0 -> row1,col0
  "rty",   // group 1 -> row1,col1
  "uiop",  // group 2 -> row1,col2
  "asd",   // group 3 -> row2,col0
  "fgh",   // group 4 -> row2,col1
  "jkl",   // group 5 -> row2,col2
  "zxc",   // group 6 -> row3,col0
  "vbnm"   // group 7 -> row3,col2
};

final int ACTION_NONE      = 0;
final int ACTION_DELETE    = 1;
final int ACTION_SPACE     = 2;
final int ACTION_SUGGEST_0 = 3; // Word (2 options)
final int ACTION_SUGGEST_1 = 4; // Next Letter (1 option)
final int ACTION_SUGGEST_2 = 5; // Next Chunk (1 option)
final int ACTION_GROUP_BASE = 100;

HashMap<String, Integer>                    wordFreq   = new HashMap<String, Integer>();
HashMap<String, HashMap<String, Integer>>   bigramFreq = new HashMap<>();
HashMap<Character, Float>                   letterWeight = new HashMap<Character, Float>();

// Maps for letter chunks
HashMap<String, Integer>                    letterBigramFreq = new HashMap<String, Integer>();
HashMap<String, Integer>                    letterTrigramFreq = new HashMap<String, Integer>();

// indices: 0,1 = words; 2 = single letter; 3 = chunk
String[] visibleSuggestions  = {"", "", "", ""};
String[] defaultSuggestions  = {"the", "and"};

int     activeGroup           = -1;
int     activeBestLetterIndex = -1; // Tracks the most likely letter in the pressed group
int     activeSuggestionGroup = -1;
int     activeTapAction       = ACTION_NONE;
boolean selectionMoved        = false;
float   pressX = 0, pressY = 0;
float   dragX  = 0, dragY  = 0;

// ── Trace trail ──────────────────────────────────────────────────────────────
final int TRAIL_LEN = 32;
float[] trailX = new float[TRAIL_LEN];
float[] trailY = new float[TRAIL_LEN];
int     trailHead = 0;   
int     trailCount = 0;  
// ─────────────────────────────────────────────────────────────────────────────

void setup()
{
  watch      = loadImage("watchhand3smaller.png");
  phrases    = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());
  loadLanguageModel();
  initLetterWeights();

  orientation(LANDSCAPE);
  size(800, 800);
  textFont(createFont("Arial", 24));
  noStroke();

  noCursor();
  mouseCursor   = loadImage("finger.png");
  cursorHeight  = DPIofYourDeviceScreen * (400.0/250.0);
  cursorWidth   = cursorHeight * 0.6;
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

  if (startTime == 0 && mousePressed)  nextTrial();
  if (startTime != 0)                  drawOutsideUI();

  image(mouseCursor,
        mouseX + cursorWidth/2 - cursorWidth/3,
        mouseY + cursorHeight/2 - cursorHeight/5,
        cursorWidth, cursorHeight);
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawing
// ─────────────────────────────────────────────────────────────────────────────

void drawInputArea()
{
  fill(34);
  rect(inputLeft(), inputTop(), sizeOfInputArea, sizeOfInputArea, 18);
  fill(50);
  rect(inputLeft()+4, inputTop()+4, sizeOfInputArea-8, sizeOfInputArea-8, 15);

  if (activeGroup >= 0)
    drawSelectionMode();
  else if (activeSuggestionGroup == 0) 
    drawSuggestionDragMode();
  else
    drawHomeKeyboard();
}

void drawHomeKeyboard()
{
  refreshVisibleSuggestions();
  textAlign(CENTER, CENTER);

  for (int col = 0; col < 4; col++)
  {
    int action = (col == 0) ? ACTION_DELETE : ACTION_SUGGEST_0 + (col - 1);
    float x = topRowLeft(col) + buttonInset();
    float y = inputTop() + buttonInset();
    float w = topRowWidth(col) - buttonInset()*2;
    float h = homeCellHeight() - buttonInset()*2;
    drawHomeButton(action, x, y, w, h);
  }

  for (int row = 1; row < 4; row++)
  {
    for (int col = 0; col < 3; col++)
    {
      int action = homeActionAt(row, col);
      float x = homeCellLeft(col) + buttonInset();
      float y = homeCellTop(row) + buttonInset();
      float w = homeCellWidth() - buttonInset()*2;
      float h = homeCellHeight() - buttonInset()*2;
      drawHomeButton(action, x, y, w, h);
    }
  }
}

void drawHomeButton(int action, float x, float y, float w, float h)
{
  boolean enabled   = actionEnabled(action);
  boolean isPressed = (action == activeTapAction) || groupPressed(action);
  String  label     = actionLabel(action);

  fill(homeButtonColor(action, enabled, isPressed));
  rect(x, y, w, h, 10);

  if (action >= ACTION_GROUP_BASE)
  {
    drawGroupPreview(action - ACTION_GROUP_BASE, x, y, w, h, isPressed);
  }
  else if (action == ACTION_SUGGEST_0)
  {
    drawWordSuggestionPreview(x, y, w, h, enabled, isPressed);
  }
  else if (action == ACTION_SUGGEST_1 || action == ACTION_SUGGEST_2)
  {
    fill(enabled ? (isPressed ? color(20) : color(248)) : color(170));
    textSize(16); 
    String txt = suggestionGroupPreviewLabel(action - ACTION_SUGGEST_0);
    text(drawChoiceLabel(txt, 4, false), x+w/2, y+h/2-2);
  }
  else
  {
    fill(enabled ? (isPressed ? color(20) : color(248)) : color(170));
    textSize(labelSize(label));
    text(drawLabel(label), x+w/2, y+h/2+1);
  }
}

void drawSelectionMode()
{
  String group = GROUPS[activeGroup];
  int hovered = selectionMoved ? activeLetterIndex() : activeBestLetterIndex;

  drawSwipeTrail();
  textAlign(CENTER, CENTER);

  // If the user drags outside the keyboard, show the Cancel overlay
  if (hovered == -2) {
    fill(220, 80, 80); 
    ellipse(inputCenterX(), inputTop() + sizeOfInputArea/2, sizeOfInputArea*0.4, sizeOfInputArea*0.4);
    fill(255);
    textSize(sizeOfInputArea*0.25);
    text("X", inputCenterX(), inputTop() + sizeOfInputArea/2 - textAscent()*0.1);
    fill(250);
    textSize(9);
    text("release to cancel", inputCenterX(), inputTop() + sizeOfInputArea - 8);
    return;
  }

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot      = selectionSlotCenter(group.length(), i);
    boolean isBest    = (i == activeBestLetterIndex);
    float   boxWidth  = selectionBoxWidth(group.length()) * (isBest ? 1.15f : 1.0f);
    float   boxHeight = selectionBoxHeight(group.length()) * (isBest ? 1.15f : 1.0f);
    boolean isHov     = (i == hovered);

    if (isHov)
    {
      float pulse = sin(millis() * 0.008) * 4;
      fill(color(246, 206, 92));
      rect(slot.x - boxWidth/2 - pulse, slot.y - boxHeight/2 - pulse,
           boxWidth + pulse*2, boxHeight + pulse*2, 16);
    }
    else
    {
      fill(isBest ? color(110, 130, 140) : color(95)); 
      rect(slot.x - boxWidth/2, slot.y - boxHeight/2, boxWidth, boxHeight, 14);
    }

    fill(isHov ? color(20) : color(248));
    float baseTextSize = group.length() == 4 ? 34 : 38;
    textSize(isBest ? baseTextSize * 1.15f : baseTextSize);
    text(group.charAt(i), slot.x, slot.y+1);
  }

  fill(250);
  textSize(9);
  text("tap for best letter · slide outside to cancel", inputCenterX(), inputTop() + sizeOfInputArea - 8);
}

void drawSuggestionDragMode()
{
  int count = suggestionOptionCount(0); 
  int hovered = selectionMoved ? activeWordSuggestionIndex() : -1;

  drawSwipeTrail();
  textAlign(CENTER, CENTER);

  // If the user drags outside the keyboard, show the Cancel overlay
  if (hovered == -2) {
    fill(220, 80, 80); 
    ellipse(inputCenterX(), inputTop() + sizeOfInputArea/2, sizeOfInputArea*0.4, sizeOfInputArea*0.4);
    fill(255);
    textSize(sizeOfInputArea*0.25);
    text("X", inputCenterX(), inputTop() + sizeOfInputArea/2 - textAscent()*0.1);
    fill(250);
    textSize(9);
    text("release to cancel", inputCenterX(), inputTop() + sizeOfInputArea - 8);
    return;
  }

  for (int i = 0; i < count; i++)
  {
    PVector slot = suggestionDragSlotCenter(count, i);
    float boxWidth = sizeOfInputArea * 0.75;
    float boxHeight = count == 1 ? sizeOfInputArea * 0.35 : sizeOfInputArea * 0.25;
    boolean isHov = (i == hovered);

    if (isHov)
    {
      float pulse = sin(millis() * 0.008) * 4;
      fill(color(246, 206, 92));
      rect(slot.x - boxWidth/2 - pulse, slot.y - boxHeight/2 - pulse,
           boxWidth + pulse*2, boxHeight + pulse*2, 16);
    }
    else
    {
      fill(color(92, 120, 138));
      rect(slot.x - boxWidth/2, slot.y - boxHeight/2, boxWidth, boxHeight, 14);
    }

    fill(isHov ? color(20) : color(248));
    String word = suggestionWord(0, i);
    
    float baseTextSize = (count == 1) ? 36 : 24;
    float widthFactor = word.length() * 0.55f; 
    float maxAllowedSize = (boxWidth * 0.9f) / Math.max(1, widthFactor);
    textSize(Math.min(baseTextSize, maxAllowedSize)); 
    text(word, slot.x, slot.y - textAscent()*0.1);
  }

  fill(250);
  textSize(9);
  text("slide outside to cancel", inputCenterX(), inputTop() + sizeOfInputArea - 8);
}

void drawSwipeTrail() 
{
  if (trailCount > 1)
  {
    strokeWeight(4);
    for (int k = 0; k < trailCount - 1; k++)
    {
      int   i0  = (trailHead - trailCount + k   + TRAIL_LEN) % TRAIL_LEN;
      int   i1  = (trailHead - trailCount + k+1 + TRAIL_LEN) % TRAIL_LEN;
      float age = (float)k / trailCount;          
      stroke(246, 206, 92, (int)(age * 180));
      line(trailX[i0], trailY[i0], trailX[i1], trailY[i1]);
    }
    noStroke();
  }
}

void drawOutsideUI()
{
  textAlign(LEFT, CENTER);
  fill(128);
  textSize(24);
  text("Phrase " + (currTrialNum+1) + " of " + totalTrialNum, 70, 50);
  text("Target:   " + currentPhrase, 70, 100);
  text("Entered:  " + currentTyped + "|", 70, 140);

  fill(255, 0, 0);
  rect(600, 600, 200, 200);
  fill(255);
  text("NEXT > ", 650, 650);
}

// ─────────────────────────────────────────────────────────────────────────────
// Mouse events
// ─────────────────────────────────────────────────────────────────────────────

boolean didMouseClick(float x, float y, float w, float h)
{
  return mouseX>x && mouseX<x+w && mouseY>y && mouseY<y+h;
}

boolean pointInRect(float px, float py, float x, float y, float w, float h)
{
  return px >= x && px <= x + w && py >= y && py <= y + h;
}

void mousePressed()
{
  if (finishTime != 0) return;
  if (didMouseClick(580, 580, 180, 90)) { nextTrial(); return; }
  if (startTime == 0) return;
  if (!isInsideInput(mouseX, mouseY)) return;

  refreshVisibleSuggestions();

  if (activeGroup >= 0 || activeSuggestionGroup >= 0) return;

  pressX = mouseX;  pressY = mouseY;
  dragX  = mouseX;  dragY  = mouseY;
  selectionMoved  = false;
  activeTapAction = ACTION_NONE;
  activeGroup     = -1;
  activeSuggestionGroup = -1;

  trailHead  = 0;
  trailCount = 0;
  trailX[0]  = mouseX;
  trailY[0]  = mouseY;
  trailHead  = 1;
  trailCount = 1;

  int action = actionAt(mouseX, mouseY);
  
  if (action >= ACTION_GROUP_BASE) {
    activeGroup = action - ACTION_GROUP_BASE;
    activeBestLetterIndex = calculateBestLetterInGroup(activeGroup);
  }
  else if (action == ACTION_SUGGEST_0) {
    activeSuggestionGroup = 0;
  }
  else {
    activeTapAction = action;
  }
}

void mouseDragged()
{
  if (activeTapAction == ACTION_NONE && activeGroup < 0 && activeSuggestionGroup < 0) return;

  // Unconstrained so user can drag off the keyboard to cancel
  dragX = mouseX;
  dragY = mouseY;

  if (dist(pressX, pressY, dragX, dragY) > 8) selectionMoved = true;

  trailX[trailHead] = dragX;
  trailY[trailHead] = dragY;
  trailHead  = (trailHead + 1) % TRAIL_LEN;
  trailCount = min(trailCount + 1, TRAIL_LEN);
}

void mouseReleased()
{
  if (activeTapAction == ACTION_NONE && activeGroup < 0 && activeSuggestionGroup < 0) return;

  dragX = mouseX;
  dragY = mouseY;

  if (activeGroup >= 0) handleLetterRelease();
  else if (activeSuggestionGroup >= 0) handleWordSuggestionRelease();
  else handleTapRelease();

  activeTapAction = ACTION_NONE;
  activeGroup     = -1;
  activeSuggestionGroup = -1;
  selectionMoved  = false;
  trailCount = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Action handling
// ─────────────────────────────────────────────────────────────────────────────

void handleTapRelease()
{
  if (!isInsideInput(dragX, dragY)) return; // Allow canceling single-tap keys like Delete/Space

  int releasedAction = actionAt(dragX, dragY);
  if (releasedAction != activeTapAction) return;

  if (activeTapAction == ACTION_DELETE)
  {
    if (currentTyped.length() > 0)
      currentTyped = currentTyped.substring(0, currentTyped.length()-1);
  }
  else if (activeTapAction == ACTION_SPACE)
  {
    currentTyped += " ";
  }
  else if (activeTapAction == ACTION_SUGGEST_1)
  {
    applySuggestion(suggestionWord(1, 0), 1);
  }
  else if (activeTapAction == ACTION_SUGGEST_2)
  {
    applySuggestion(suggestionWord(2, 0), 2);
  }
}

void handleLetterRelease()
{
  int letterIndex = -1;
  
  if (!selectionMoved) {
      letterIndex = activeBestLetterIndex;
  } else {
      letterIndex = activeLetterIndex();
  }
  
  if (letterIndex == -2) return; // Action was cancelled by user dragging out of bounds
  
  currentTyped += GROUPS[activeGroup].charAt(letterIndex);
}

void handleWordSuggestionRelease()
{
  if (!selectionMoved) {
      applySuggestion(suggestionWord(0, 0), 0);
      return;
  }
  
  int suggestionIndex = activeWordSuggestionIndex();
  
  if (suggestionIndex == -2) return; // Action was cancelled by user dragging out of bounds
  
  if (suggestionIndex >= 0)
    applySuggestion(suggestionWord(0, suggestionIndex), 0);
}

void applySuggestion(String word, int groupIndex)
{
  if (word == null || word.trim().equals("")) return;
  
  if (groupIndex > 0)
  {
    currentTyped += word; 
  }
  else
  {
    String prefix = currentWordPrefix();
    if (prefix.length() > 0)
    {
      int    lastSpace = currentTyped.lastIndexOf(' ');
      String base      = lastSpace >= 0 ? currentTyped.substring(0, lastSpace+1) : "";
      currentTyped = base + word + " ";
    }
    else
    {
      currentTyped += word + " ";
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prefix-Aware Suggestions
// ─────────────────────────────────────────────────────────────────────────────

void refreshVisibleSuggestions()
{
  String[] next = computeVisibleSuggestions();
  for (int i = 0; i < 4; i++)
    visibleSuggestions[i] = next[i];
}

int calculateBestLetterInGroup(int gIndex) 
{
  String group = GROUPS[gIndex];
  String prevWord = previousContextWord().toLowerCase();
  String prefix = currentWordPrefix().toLowerCase();
  int bestIdx = 0;
  float bestScore = -1;

  for (int i = 0; i < group.length(); i++) {
    char c = group.charAt(i);
    float score = letterWeight.containsKey(c) ? letterWeight.get(c) : 0.0f;
    String candidate = prefix + c;
    
    if (prevWord.length() > 0 && bigramFreq.containsKey(prevWord)) {
      HashMap<String, Integer> nxt = bigramFreq.get(prevWord);
      for (String w : nxt.keySet()) {
        if (w.startsWith(candidate)) {
          score += 10.0f; // High boost for matching context
          break;
        }
      }
    } 
    for (String w : wordFreq.keySet()) {
      if (w.startsWith(candidate)) {
        score += 2.0f; // Slight boost for matching dictionary
        break;
      }
    }

    if (score > bestScore) {
      bestScore = score;
      bestIdx = i;
    }
  }
  return bestIdx;
}

String[] computeVisibleSuggestions()
{
  String[] result = new String[4];
  String prefix   = currentWordPrefix().toLowerCase();
  String prevWord = previousContextWord().toLowerCase();

  String[] bestWords = {"", ""};
  int[] freqsWords = {-1, -1};

  if (prefix.length() == 0) 
  {
    if (prevWord.length() > 0 && bigramFreq.containsKey(prevWord))
    {
      HashMap<String, Integer> nextWords = bigramFreq.get(prevWord);
      for (String w : nextWords.keySet()) 
         addCandidate(w, nextWords.get(w), bestWords, freqsWords);
    }
    
    for(int i = 0; i < bestWords.length; i++) {
       if (!bestWords[i].equals("")) freqsWords[i] = Integer.MAX_VALUE;
       else freqsWords[i] = -1;
    }
    
    for (String w : wordFreq.keySet()) {
       addCandidate(w, wordFreq.get(w), bestWords, freqsWords);
    }
    
    result[0] = bestWords[0].equals("") ? defaultSuggestions[0] : bestWords[0];
    result[1] = bestWords[1].equals("") ? defaultSuggestions[1] : bestWords[1];

    String bestStartLetter = "t";
    String bestStartChunk = "th";

    if (prevWord.length() > 0 && bigramFreq.containsKey(prevWord)) {
        HashMap<String, Integer> nextLetters = new HashMap<>();
        HashMap<String, Integer> nextChunks = new HashMap<>();

        for (String w : bigramFreq.get(prevWord).keySet()) {
            int f = bigramFreq.get(prevWord).get(w);
            if (w.length() >= 1) {
                String l = w.substring(0, 1);
                nextLetters.put(l, nextLetters.getOrDefault(l, 0) + f);
            }
            if (w.length() >= 2) {
                String c = w.substring(0, 2);
                nextChunks.put(c, nextChunks.getOrDefault(c, 0) + f);
            }
        }

        int maxL = -1;
        for (String k : nextLetters.keySet()) {
            if (nextLetters.get(k) > maxL) { maxL = nextLetters.get(k); bestStartLetter = k; }
        }
        int maxC = -1;
        for (String k : nextChunks.keySet()) {
            if (nextChunks.get(k) > maxC) { maxC = nextChunks.get(k); bestStartChunk = k; }
        }
    }

    result[2] = bestStartLetter;
    result[3] = bestStartChunk;
  } 
  else 
  {
    HashMap<String, Integer> possibleWords = new HashMap<>();
    
    if (prevWord.length() > 0 && bigramFreq.containsKey(prevWord))
    {
      HashMap<String, Integer> nextWords = bigramFreq.get(prevWord);
      for (String w : nextWords.keySet()) {
         if (w.startsWith(prefix) && w.length() > prefix.length()) {
             possibleWords.put(w, nextWords.get(w) * 1000); 
         }
      }
    }

    for (String w : wordFreq.keySet())
    {
      if (w.startsWith(prefix) && w.length() > prefix.length()) {
          possibleWords.put(w, possibleWords.getOrDefault(w, 0) + wordFreq.get(w));
      }
    }

    HashMap<String, Integer> letterFreqs = new HashMap<>();
    HashMap<String, Integer> chunkFreqs = new HashMap<>();

    for (String w : possibleWords.keySet()) {
        int f = possibleWords.get(w);
        addCandidate(w, f, bestWords, freqsWords);
        
        String nextL = w.substring(prefix.length(), prefix.length() + 1);
        letterFreqs.put(nextL, letterFreqs.getOrDefault(nextL, 0) + f);
        
        if (w.length() >= prefix.length() + 2) {
            String nextC = w.substring(prefix.length(), prefix.length() + 2);
            chunkFreqs.put(nextC, chunkFreqs.getOrDefault(nextC, 0) + f);
        }
    }

    result[0] = bestWords[0];
    result[1] = bestWords[1];

    String bestSingle = ""; int maxL = -1;
    for (String k : letterFreqs.keySet()) {
        if (letterFreqs.get(k) > maxL) { maxL = letterFreqs.get(k); bestSingle = k; }
    }
    
    String bestDouble = ""; int maxC = -1;
    for (String k : chunkFreqs.keySet()) {
        if (chunkFreqs.get(k) > maxC) { maxC = chunkFreqs.get(k); bestDouble = k; }
    }

    if (bestDouble.equals(bestSingle)) bestDouble = "";

    result[2] = bestSingle;
    result[3] = bestDouble;
  }
  
  for (int i = 0; i < 4; i++) {
     if (result[i] == null || result[i].equals("")) result[i] = " ";
  }
  return result;
}

void addCandidate(String w, int f, String[] best, int[] freqs) {
  for (int i = 0; i < best.length; i++) {
    if (w.equals(best[i])) return; 
  }
  for (int i = 0; i < best.length; i++) {
    if (f > freqs[i]) {
      for (int j = best.length - 1; j > i; j--) {
        freqs[j] = freqs[j - 1];
        best[j]  = best[j - 1];
      }
      freqs[i] = f;
      best[i]  = w;
      break;
    }
  }
}

String currentWordPrefix()
{
  if (currentTyped.length()==0 || currentTyped.charAt(currentTyped.length()-1)==' ')
    return "";
  int lastSpace = currentTyped.lastIndexOf(' ');
  return lastSpace < 0 ? currentTyped : currentTyped.substring(lastSpace+1);
}

String previousContextWord()
{
  if (currentTyped.length()==0) return "";
  int end = currentTyped.length()-1;
  while (end>=0 && currentTyped.charAt(end)==' ') end--;
  if (end < 0) return "";
  if (currentTyped.charAt(currentTyped.length()-1) != ' ')
  {
    while (end>=0 && currentTyped.charAt(end)!=' ') end--;
    while (end>=0 && currentTyped.charAt(end)==' ') end--;
    if (end < 0) return "";
  }
  int start = end;
  while (start>=0 && currentTyped.charAt(start)!=' ') start--;
  return currentTyped.substring(start+1, end+1);
}

int suggestionGroupStart(int suggestionGroup)
{
  if (suggestionGroup == 0) return 0;
  if (suggestionGroup == 1) return 2;
  if (suggestionGroup == 2) return 3;
  return 0;
}

int suggestionOptionCount(int suggestionGroup)
{
  if (suggestionGroup == 0) {
      int count = 0;
      if (visibleSuggestions[0] != null && visibleSuggestions[0].trim().length() > 0) count++;
      if (visibleSuggestions[1] != null && visibleSuggestions[1].trim().length() > 0) count++;
      return count;
  } else if (suggestionGroup == 1) {
      return (visibleSuggestions[2] != null && visibleSuggestions[2].trim().length() > 0) ? 1 : 0;
  } else if (suggestionGroup == 2) {
      return (visibleSuggestions[3] != null && visibleSuggestions[3].trim().length() > 0) ? 1 : 0;
  }
  return 0;
}

String suggestionWord(int suggestionGroup, int optionIndex)
{
  int index = suggestionGroupStart(suggestionGroup) + optionIndex;
  return visibleSuggestions[index];
}

String suggestionGroupPreviewLabel(int suggestionGroup)
{
  if (suggestionOptionCount(suggestionGroup) == 0) return "";
  return suggestionWord(suggestionGroup, 0);
}

String drawChoiceLabel(String label, int maxChars, boolean showEllipsis)
{
  if (label == null || label.trim().length() == 0) return " ";
  if (label.length() <= maxChars) return label;
  
  if (showEllipsis) return label.substring(0, maxChars - 1) + "…";
  return label.substring(0, maxChars);
}

void drawWordSuggestionPreview(float x, float y, float w, float h, boolean enabled, boolean isPressed)
{
  int count = suggestionOptionCount(0);

  if (count == 0)
  {
    fill(enabled ? color(248) : color(170));
    textSize(9);
    text("empty", x + w / 2, y + h / 2 + 1);
    return;
  }

  float miniHeight = count == 1 ? h * 0.48 : h * 0.30;
  float gap = h * 0.08;
  float totalHeight = count * miniHeight + (count - 1) * gap;
  float startY = y + (h - totalHeight) / 2.0;

  for (int i = 0; i < count; i++)
  {
    float miniY = startY + i * (miniHeight + gap);
    fill(isPressed ? color(255, 240, 188) : color(118, 144, 160));
    rect(x + w * 0.10, miniY, w * 0.80, miniHeight, 7);

    fill(isPressed ? color(20) : color(248));
    String word = suggestionWord(0, i);
    
    float baseTextSize = (count == 1) ? 14 : 10;
    float widthFactor = word.length() * 0.5f; 
    float maxAllowedSize = (w * 0.75f) / Math.max(1, widthFactor);
    textSize(Math.min(baseTextSize, maxAllowedSize));
    
    text(word, x + w / 2, miniY + miniHeight / 2 + 1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag Selection Calculations (Hitbox Gravity & Cancellation)
// ─────────────────────────────────────────────────────────────────────────────

int activeLetterIndex()
{
  // CANCEL if dragged outside of the grey smartwatch boundary
  if (!isInsideInput(dragX, dragY)) return -2; 
  
  String group = GROUPS[activeGroup];
  float dragDist = dist(pressX, pressY, dragX, dragY);
  
  if (dragDist < sizeOfInputArea * 0.18f) {
    return activeBestLetterIndex; 
  }

  int bestIndex = 0;
  float bestDistance = Float.MAX_VALUE;

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot = selectionSlotCenter(group.length(), i);
    float distance = dist(dragX, dragY, slot.x, slot.y);

    float bias = (i == activeBestLetterIndex) ? (sizeOfInputArea * 0.15f) : 0;
    float score = distance - bias;
    
    if (score < bestDistance) { bestDistance = score; bestIndex = i; }
  }
  return bestIndex;
}

int activeWordSuggestionIndex()
{
  // CANCEL if dragged outside of the grey smartwatch boundary
  if (!isInsideInput(dragX, dragY)) return -2;

  int count = suggestionOptionCount(0);
  if (count <= 1) return 0;
  
  float dragDist = dist(pressX, pressY, dragX, dragY);
  if (dragDist < sizeOfInputArea * 0.18f) {
    return 0; 
  }
  
  int bestIndex = 0;
  float bestScore = Float.MAX_VALUE;

  for (int i = 0; i < count; i++)
  {
    PVector slot = suggestionDragSlotCenter(count, i);
    float distance = dist(dragX, dragY, slot.x, slot.y);
    if (distance < bestScore) { bestScore = distance; bestIndex = i; }
  }
  return bestIndex;
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid layout
// ─────────────────────────────────────────────────────────────────────────────

float topRowWidth(int col) {
  if (col == 0) return sizeOfInputArea * 0.25;
  if (col == 1) return sizeOfInputArea * 0.35;
  return sizeOfInputArea * 0.20;
}

float topRowLeft(int col) {
  if (col == 0) return inputLeft();
  if (col == 1) return inputLeft() + sizeOfInputArea * 0.25;
  if (col == 2) return inputLeft() + sizeOfInputArea * 0.60;
  return inputLeft() + sizeOfInputArea * 0.80;
}

int actionAt(float x, float y)
{
  int row = constrain((int)((y - inputTop())  / homeCellHeight()), 0, 3);
  
  if (row == 0)
  {
    float relX = x - inputLeft();
    if (relX < sizeOfInputArea * 0.25) return ACTION_DELETE;
    if (relX < sizeOfInputArea * 0.60) return ACTION_SUGGEST_0;
    if (relX < sizeOfInputArea * 0.80) return ACTION_SUGGEST_1;
    return ACTION_SUGGEST_2;
  }
  
  int col = constrain((int)((x - inputLeft()) / homeCellWidth()),  0, 2);
  return homeActionAt(row, col);
}

int homeActionAt(int row, int col)
{
  if (row == 1) return ACTION_GROUP_BASE + col;          
  if (row == 2) return ACTION_GROUP_BASE + (col + 3);    
  if (row == 3) {
    if (col == 0) return ACTION_GROUP_BASE + 6;            
    if (col == 1) return ACTION_SPACE;
    return ACTION_GROUP_BASE + 7;                          
  }
  return ACTION_NONE;
}

boolean groupPressed(int action)
{
  if (action < ACTION_GROUP_BASE) return false;
  return activeGroup == action - ACTION_GROUP_BASE && !selectionMoved;
}

boolean actionEnabled(int action)
{
  if (action >= ACTION_SUGGEST_0 && action <= ACTION_SUGGEST_2)
    return suggestionOptionCount(action - ACTION_SUGGEST_0) > 0;
  return true;
}

int homeButtonColor(int action, boolean enabled, boolean isPressed)
{
  if (!enabled)  return color(78);
  if (isPressed) return color(246, 206, 92);
  if (action == ACTION_DELETE)    return color(118);
  if (action == ACTION_SPACE)     return color(175);
  if (action >= ACTION_SUGGEST_0 && action <= ACTION_SUGGEST_2)
    return color(88, 116, 132);
  return color(90);
}

String actionLabel(int action)
{
  if (action == ACTION_DELETE)    return "del";
  if (action == ACTION_SPACE)     return "space";
  if (action >= ACTION_SUGGEST_0 && action <= ACTION_SUGGEST_2)
    return suggestionGroupPreviewLabel(action - ACTION_SUGGEST_0);
  return GROUPS[action - ACTION_GROUP_BASE];
}

String drawLabel(String label)
{
  if (label==null || label.length()==0) return " ";
  return label.length()<=8 ? label : label.substring(0,8);
}

float labelSize(String label)
{
  if (label==null)          return 11;
  if (label.length()<=4)    return 13;
  if (label.length()<=8)    return 10;
  return 9;
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometry helpers
// ─────────────────────────────────────────────────────────────────────────────

boolean isInsideInput(float x, float y)
{
  return x>=inputLeft() && x<=inputLeft()+sizeOfInputArea
      && y>=inputTop()  && y<=inputTop()+sizeOfInputArea;
}

float inputLeft()   { return width/2.0  - sizeOfInputArea/2.0; }
float inputTop()    { return height/2.0 - sizeOfInputArea/2.0; }
float inputCenterX(){ return width/2.0; }
float homeCellWidth() { return sizeOfInputArea/3.0; }
float homeCellHeight(){ return sizeOfInputArea/4.0; }
float homeCellLeft(int col){ return inputLeft() + col*homeCellWidth(); }
float homeCellTop (int row){ return inputTop()  + row*homeCellHeight(); }
float buttonInset() { return 3; }

// ─────────────────────────────────────────────────────────────────────────────
// Group preview (small letter tiles shown on home keys)
// ─────────────────────────────────────────────────────────────────────────────

void drawGroupPreview(int groupIndex, float x, float y, float w, float h, boolean isPressed)
{
  String group = GROUPS[groupIndex];
  float tw = previewBoxWidth(group.length(), w);
  float th = previewBoxHeight(group.length(), h);

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot = previewSlotCenter(group.length(), i, x, y, w, h);
    fill(isPressed ? color(255,240,188) : color(126));
    rect(slot.x - tw/2, slot.y - th/2, tw, th, 6);
    fill(isPressed ? color(20) : color(248));
    textSize(group.length()==4 ? 13 : 14);
    text(group.charAt(i), slot.x, slot.y+1);
  }
}

PVector previewSlotCenter(int groupLength, int index, float x, float y, float w, float h)
{
  float[] pos = slotPosition(groupLength, index);
  return new PVector(x + w*pos[0], y + h*pos[1]);
}

PVector selectionSlotCenter(int groupLength, int index)
{
  float[] pos = selectionSlotPosition(groupLength, index);
  
  float mx = sizeOfInputArea * 0.10; 
  float my = sizeOfInputArea * 0.10;
  
  return new PVector(
    inputLeft() + mx + (sizeOfInputArea - mx*2) * pos[0],
    inputTop()  + my + (sizeOfInputArea - my*2) * pos[1]);
}

PVector suggestionDragSlotCenter(int count, int index)
{
  if (count == 1) return new PVector(inputCenterX(), inputTop() + sizeOfInputArea/2.0);
  
  float mx = sizeOfInputArea * 0.50; 
  float my0 = sizeOfInputArea * 0.32; 
  float my1 = sizeOfInputArea * 0.68;
  
  if (index == 0) return new PVector(inputLeft() + mx, inputTop() + my0);
  else return new PVector(inputLeft() + mx, inputTop() + my1);
}

float[] slotPosition(int groupLength, int index)
{
  if (groupLength == 4)
  {
    if (index==0) return new float[]{0.28, 0.28};
    if (index==1) return new float[]{0.72, 0.28};
    if (index==2) return new float[]{0.28, 0.72};
    return new float[]{0.72, 0.72};
  }
  if (index==0) return new float[]{0.28, 0.32};
  if (index==1) return new float[]{0.72, 0.32};
  return new float[]{0.50, 0.74};
}

float[] selectionSlotPosition(int groupLength, int index)
{
  if (groupLength == 4)
  {
    if (index==0) return new float[]{0.15f, 0.15f};
    if (index==1) return new float[]{0.85f, 0.15f};
    if (index==2) return new float[]{0.15f, 0.85f};
    return new float[]{0.85f, 0.85f};
  }
  if (index==0) return new float[]{0.15f, 0.20f};
  if (index==1) return new float[]{0.85f, 0.20f};
  return new float[]{0.50f, 0.85f};
}

float previewBoxWidth(int len, float keyWidth)  { return len==4 ? keyWidth*0.30 : keyWidth*0.34; }
float previewBoxHeight(int len, float keyHeight) { return len==4 ? keyHeight*0.28 : keyHeight*0.30; }
float selectionBoxWidth(int len)  { return len==4 ? sizeOfInputArea*0.31 : sizeOfInputArea*0.34; }
float selectionBoxHeight(int len) { return len==4 ? sizeOfInputArea*0.31 : sizeOfInputArea*0.30; }

// ─────────────────────────────────────────────────────────────────────────────
// Language model
// ─────────────────────────────────────────────────────────────────────────────

void loadLanguageModel() { 
  loadFrequencies(); 
  loadBigrams(); 
}

void loadFrequencies()
{
  String[] lines = loadStrings("ngrams/count_1w.txt");
  if (lines != null) {
    for (String line : lines)
    {
      String[] parts = split(line, '\t');
      if (parts.length == 2) wordFreq.put(parts[0].toLowerCase(), int(parts[1]));
    }
  }
}

void loadBigrams()
{
  String[] lines = loadStrings("ngrams/count_2w.txt");
  if (lines != null) {
    for (String line : lines)
    {
      String[] parts = split(line, '\t');
      if (parts.length != 2) continue;
      String[] words = split(parts[0].toLowerCase(), ' ');
      if (words.length != 2) continue;
      int freq = int(parts[1]);
      if (!bigramFreq.containsKey(words[0]))
        bigramFreq.put(words[0], new HashMap<String, Integer>());
      bigramFreq.get(words[0]).put(words[1], freq);
    }
  }
}

void initLetterWeights()
{
  String letters = "etaoinshrdlucmfwypvbgkjqxz";
  for (int i = 0; i < letters.length(); i++)
    letterWeight.put(letters.charAt(i), 1.0 - (i * 0.03));
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum) return;

  if (startTime != 0 && finishTime == 0)
  {
    System.out.println("==================");
    System.out.println("Phrase " + (currTrialNum+1) + " of " + totalTrialNum);
    System.out.println("Target phrase: " + currentPhrase);
    System.out.println("Phrase length: " + currentPhrase.length());
    System.out.println("User typed: " + currentTyped);
    System.out.println("User typed length: " + currentTyped.length());
    System.out.println("Number of errors: " + computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim()));
    System.out.println("Time taken on this trial: " + (millis()-lastTime));
    System.out.println("Time taken since beginning: " + (millis()-startTime));
    System.out.println("==================");
    lettersExpectedTotal += currentPhrase.trim().length();
    lettersEnteredTotal  += currentTyped.trim().length();
    errorsTotal          += computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim());
  }

  if (currTrialNum == totalTrialNum-1)
  {
    finishTime = millis();
    System.out.println("==================");
    System.out.println("Trials complete!");
    System.out.println("Total time taken: " + (finishTime-startTime));
    System.out.println("Total letters entered: " + lettersEnteredTotal);
    System.out.println("Total letters expected: " + lettersExpectedTotal);
    System.out.println("Total errors entered: " + errorsTotal);
    float wpm           = (lettersEnteredTotal/5.0f) / ((finishTime-startTime)/60000f);
    float freebieErrors = lettersExpectedTotal * .05f;
    float penalty       = max(errorsTotal - freebieErrors, 0) * .5f;
    System.out.println("Raw WPM: " + wpm);
    System.out.println("Freebie errors: " + freebieErrors);
    System.out.println("Penalty: " + penalty);
    System.out.println("WPM w/ penalty: " + (wpm-penalty));
    System.out.println("==================");
    currTrialNum++;
    return;
  }

  if (startTime == 0) { System.out.println("Trials beginning! Starting timer..."); startTime = millis(); }
  else currTrialNum++;

  lastTime     = millis();
  currentTyped = "";
  currentPhrase = phrases[currTrialNum];
}

void drawWatch()
{
  float watchscale = DPIofYourDeviceScreen / 138.0f;
  pushMatrix();
  translate(width/2f, height/2f);
  scale(watchscale);
  imageMode(CENTER);
  image(watch, 0, 0);
  popMatrix();
}

//=========SHOULD NOT NEED TO TOUCH THIS METHOD AT ALL!==============
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