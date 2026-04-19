import java.io.BufferedReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Random;

// Set the DPI to make your smartwatch 1 inch square. Measure it on the screen
final int DPIofYourDeviceScreen = 125; //you will need to look up the DPI or PPI of your device to make sure you get the right scale!!
//http://en.wikipedia.org/wiki/List_of_displays_by_pixel_density

//Do not change the following variables
String[] phrases; //contains all of the phrases
String[] suggestions; //contains all of the phrases
int totalTrialNum = 3 + (int)random(3); //the total number of phrases to be tested - set this low for testing. Might be ~10 for the real bakeoff!
int currTrialNum = 0; // the current trial number (indexes into trials array above)
float startTime = 0; // time starts when the first letter is entered
float finishTime = 0; // records the time of when the final trial ends
float lastTime = 0; //the timestamp of when the last trial was completed
float lettersEnteredTotal = 0; //a running total of the number of letters the user has entered (need this for final WPM computation)
float lettersExpectedTotal = 0; //a running total of the number of letters expected (correct phrases)
float errorsTotal = 0; //a running total of the number of errors (when hitting next)
String currentPhrase = ""; //the current target phrase
String currentTyped = ""; //what the user has typed so far
final float sizeOfInputArea = DPIofYourDeviceScreen*1; //aka, 1.0 inches square!
PImage watch;
PImage mouseCursor;
float cursorHeight;
float cursorWidth;

// QWERTY-mapped groups: 3 rows × 3 cols = 9 groups (last row has space/del/suggest in row 0)
// Layout on the 3×4 grid:
//   Row 0: [del] [suggest0] [suggest1]
//   Row 1: [qwe] [rty]     [uiop]
//   Row 2: [asd] [fgh]     [jkl]
//   Row 3: [zxc] [space]   [vbnm]
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
final int ACTION_SUGGEST_0 = 3;
final int ACTION_SUGGEST_1 = 4;
final int ACTION_GROUP_BASE = 100;

final int SUGGESTION_SLOTS  = 2;

HashMap<String, Integer>                    wordFreq   = new HashMap<String, Integer>();
HashMap<String, HashMap<String, Integer>>   bigramFreq = new HashMap<>();
HashMap<Character, Float>                   letterWeight = new HashMap<Character, Float>();
String[] visibleSuggestions  = {"", ""};
String[] defaultSuggestions  = {"the", "and"};

int     activeGroup     = -1;
int     activeTapAction = ACTION_NONE;
boolean selectionMoved  = false;
float   pressX = 0, pressY = 0;
float   dragX  = 0, dragY  = 0;

// ── Trace trail ──────────────────────────────────────────────────────────────
// We record the last N drag positions so we can draw a fading swipe trail
// while the user is sliding within a group.
final int TRAIL_LEN = 32;
float[] trailX = new float[TRAIL_LEN];
float[] trailY = new float[TRAIL_LEN];
int     trailHead = 0;   // ring-buffer head
int     trailCount = 0;  // how many valid points we have
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
  else
    drawHomeKeyboard();
}

void drawHomeKeyboard()
{
  refreshVisibleSuggestions();
  textAlign(CENTER, CENTER);

  for (int row = 0; row < 4; row++)
  {
    for (int col = 0; col < 3; col++)
    {
      int     action    = homeActionAt(row, col);
      float   x         = homeCellLeft(col)  + buttonInset();
      float   y         = homeCellTop(row)   + buttonInset();
      float   w         = homeCellWidth()    - buttonInset()*2;
      float   h         = homeCellHeight()   - buttonInset()*2;
      String  label     = actionLabel(action);
      boolean enabled   = actionEnabled(action);
      boolean isPressed = (action == activeTapAction) || groupPressed(action);

      fill(homeButtonColor(action, enabled, isPressed));
      rect(x, y, w, h, 10);

      if (action >= ACTION_GROUP_BASE)
        drawGroupPreview(action - ACTION_GROUP_BASE, x, y, w, h, isPressed);
      else
      {
        fill(enabled ? (isPressed ? color(20) : color(248)) : color(170));
        textSize(labelSize(label));
        text(drawLabel(label), x+w/2, y+h/2+1);
      }
    }
  }
}

// Full-screen letter picker with trace trail
void drawSelectionMode()
{
  String group      = GROUPS[activeGroup];
  int    hovered    = selectionMoved ? activeLetterIndex() : -1;

  // ── Swipe trail ──────────────────────────────────────────────────────────
  if (trailCount > 1)
  {
    strokeWeight(4);
    for (int k = 0; k < trailCount - 1; k++)
    {
      int   i0  = (trailHead - trailCount + k   + TRAIL_LEN) % TRAIL_LEN;
      int   i1  = (trailHead - trailCount + k+1 + TRAIL_LEN) % TRAIL_LEN;
      float age = (float)k / trailCount;          // 0 = oldest, 1 = newest
      stroke(246, 206, 92, (int)(age * 180));
      line(trailX[i0], trailY[i0], trailX[i1], trailY[i1]);
    }
    noStroke();
  }
  // ─────────────────────────────────────────────────────────────────────────

  textAlign(CENTER, CENTER);

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot      = selectionSlotCenter(group.length(), i);
    float   boxWidth  = selectionBoxWidth(group.length());
    float   boxHeight = selectionBoxHeight(group.length());
    boolean isHov     = (i == hovered);

    // Pulse the hovered tile
    if (isHov)
    {
      float pulse = sin(millis() * 0.008) * 4;
      fill(color(246, 206, 92));
      rect(slot.x - boxWidth/2 - pulse, slot.y - boxHeight/2 - pulse,
           boxWidth + pulse*2, boxHeight + pulse*2, 16);
    }
    else
    {
      fill(color(95));
      rect(slot.x - boxWidth/2, slot.y - boxHeight/2, boxWidth, boxHeight, 14);
    }

    fill(isHov ? color(20) : color(248));
    textSize(group.length() == 4 ? 34 : 38);
    text(group.charAt(i), slot.x, slot.y+1);
  }

  // Hint at the bottom
  fill(250);
  textSize(9);
  text("hold " + group + " · slide to letter", inputCenterX(), inputTop() + sizeOfInputArea - 8);
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

void mousePressed()
{
  if (finishTime != 0) return;
  if (didMouseClick(580, 580, 180, 90)) { nextTrial(); return; }
  if (startTime == 0) return;
  if (!isInsideInput(mouseX, mouseY)) return;

  refreshVisibleSuggestions();
  pressX = mouseX;  pressY = mouseY;
  dragX  = mouseX;  dragY  = mouseY;
  selectionMoved  = false;
  activeTapAction = ACTION_NONE;
  activeGroup     = -1;

  // Reset trace trail
  trailHead  = 0;
  trailCount = 0;
  trailX[0]  = mouseX;
  trailY[0]  = mouseY;
  trailHead  = 1;
  trailCount = 1;

  int action = actionAt(mouseX, mouseY);
  if (action >= ACTION_GROUP_BASE)
    activeGroup = action - ACTION_GROUP_BASE;
  else
    activeTapAction = action;
}

void mouseDragged()
{
  if (activeTapAction == ACTION_NONE && activeGroup < 0) return;

  dragX = constrain(mouseX, inputLeft(), inputLeft()+sizeOfInputArea);
  dragY = constrain(mouseY, inputTop(),  inputTop()+sizeOfInputArea);

  if (dist(pressX, pressY, dragX, dragY) > 8) selectionMoved = true;

  // Append to trace trail (ring buffer)
  trailX[trailHead] = dragX;
  trailY[trailHead] = dragY;
  trailHead  = (trailHead + 1) % TRAIL_LEN;
  trailCount = min(trailCount + 1, TRAIL_LEN);
}

void mouseReleased()
{
  if (activeTapAction == ACTION_NONE && activeGroup < 0) return;

  dragX = constrain(mouseX, inputLeft(), inputLeft()+sizeOfInputArea);
  dragY = constrain(mouseY, inputTop(),  inputTop()+sizeOfInputArea);

  if (activeGroup >= 0) handleLetterRelease();
  else                  handleTapRelease();

  activeTapAction = ACTION_NONE;
  activeGroup     = -1;
  selectionMoved  = false;

  // Clear trail on release
  trailCount = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Action handling
// ─────────────────────────────────────────────────────────────────────────────

void handleTapRelease()
{
  int releasedAction = actionAt(dragX, dragY);
  if (releasedAction != activeTapAction) return;

  if (activeTapAction == ACTION_DELETE)
  {
    if (currentTyped.length() > 0)
      currentTyped = currentTyped.substring(0, currentTyped.length()-1);
    return;
  }
  if (activeTapAction == ACTION_SPACE)
  {
    currentTyped += " ";
    return;
  }
  if (activeTapAction == ACTION_SUGGEST_0 || activeTapAction == ACTION_SUGGEST_1)
  {
    int idx = activeTapAction - ACTION_SUGGEST_0;
    if (idx >= 0 && idx < visibleSuggestions.length)
      applySuggestion(visibleSuggestions[idx]);
  }
}

void handleLetterRelease()
{
  if (!selectionMoved) return;
  int letterIndex = activeLetterIndex();
  currentTyped += GROUPS[activeGroup].charAt(letterIndex);
}

void applySuggestion(String word)
{
  if (word == null || word.length() == 0) return;
  String prefix = currentWordPrefix();
  if (prefix.length() > 0)
  {
    int    lastSpace = currentTyped.lastIndexOf(' ');
    String base      = lastSpace >= 0 ? currentTyped.substring(0, lastSpace+1) : "";
    currentTyped = base + word + " ";
  }
  else
    currentTyped += word + " ";
}

// ─────────────────────────────────────────────────────────────────────────────
// Suggestions
// ─────────────────────────────────────────────────────────────────────────────

void refreshVisibleSuggestions()
{
  String[] next = computeVisibleSuggestions();
  for (int i = 0; i < SUGGESTION_SLOTS; i++)
    visibleSuggestions[i] = next[i];
}

String[] computeVisibleSuggestions()
{
  String[] result = {"", ""};
  String prefix   = currentWordPrefix().toLowerCase();
  String prevWord = previousContextWord().toLowerCase();
  String best1 = "", best2 = "";
  int    f1 = -1, f2 = -1;

  if (bigramFreq.containsKey(prevWord))
  {
    HashMap<String, Integer> nextWords = bigramFreq.get(prevWord);
    for (String w : nextWords.keySet())
    {
      if (w.startsWith(prefix))
      {
        int f = nextWords.get(w);
        if (f > f1) { best2=best1; f2=f1; best1=w; f1=f; }
        else if (f > f2) { best2=w; f2=f; }
      }
    }
  }

  if (best1.equals(""))
  {
    for (String w : wordFreq.keySet())
    {
      if (w.startsWith(prefix))
      {
        int f = wordFreq.get(w);
        if (f > f1) { best2=best1; f2=f1; best1=w; f1=f; }
        else if (f > f2) { best2=w; f2=f; }
      }
    }
  }

  result[0] = best1.equals("") ? defaultSuggestions[0] : best1;
  result[1] = best2.equals("") ? defaultSuggestions[1] : best2;
  return result;
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

// ─────────────────────────────────────────────────────────────────────────────
// Letter selection within a group
// Distance always dominates. Bias is a small flat pixel bonus that only
// matters when two letters are nearly equidistant — it never overrides a
// clear drag toward a specific letter.
// ─────────────────────────────────────────────────────────────────────────────

// Maximum pixel advantage the bias can give a letter.
// Slots are ~40-50px apart on a 125dpi watch, so 6px is a ~12% nudge at most.
final float MAX_BIAS_PX = 6.0;

int activeLetterIndex()
{
  String group     = GROUPS[activeGroup];
  String prevWord  = previousContextWord().toLowerCase();
  String prefix    = currentWordPrefix().toLowerCase();
  int    bestIndex = 0;
  float  bestScore = Float.MAX_VALUE;

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot     = selectionSlotCenter(group.length(), i);
    float   distance = dist(dragX, dragY, slot.x, slot.y);
    char    c        = group.charAt(i);

    // Additive pixel bonus — never changes which letter is closer by much.
    // Starts at 0 and grows only if the letter is predicted by context.
    float bias = 0;

    // Letter-frequency nudge (small — common letters get at most MAX_BIAS_PX/2)
    float freqWeight = letterWeight.containsKey(c) ? letterWeight.get(c) : 0.5;
    bias += freqWeight * (MAX_BIAS_PX * 0.5);

    // Bigram nudge — adds up to MAX_BIAS_PX/2 more if this letter continues a known bigram
    String candidate = prefix + c;
    if (bigramFreq.containsKey(prevWord))
    {
      HashMap<String, Integer> nxt = bigramFreq.get(prevWord);
      for (String w : nxt.keySet())
      {
        if (w.startsWith(candidate))
        {
          bias += MAX_BIAS_PX * 0.5;
          break;
        }
      }
    }

    // Score = pure distance minus tiny bias. Distance is always the main factor.
    float score = distance - bias;
    if (score < bestScore) { bestScore = score; bestIndex = i; }
  }
  return bestIndex;
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid layout
// Row 0: del | suggest0 | suggest1
// Row 1: qwe | rty      | uiop        (groups 0,1,2)
// Row 2: asd | fgh      | jkl         (groups 3,4,5)
// Row 3: zxc | SPACE    | vbnm        (groups 6, space, 7)
// ─────────────────────────────────────────────────────────────────────────────

int actionAt(float x, float y)
{
  int row = constrain((int)((y - inputTop())  / homeCellHeight()), 0, 3);
  int col = constrain((int)((x - inputLeft()) / homeCellWidth()),  0, 2);
  return homeActionAt(row, col);
}

int homeActionAt(int row, int col)
{
  if (row == 0)
  {
    if (col == 0) return ACTION_DELETE;
    if (col == 1) return ACTION_SUGGEST_0;
    return ACTION_SUGGEST_1;
  }
  if (row == 1) return ACTION_GROUP_BASE + col;          // groups 0,1,2
  if (row == 2) return ACTION_GROUP_BASE + (col + 3);    // groups 3,4,5
  // row 3
  if (col == 0) return ACTION_GROUP_BASE + 6;            // group 6 (zxc)
  if (col == 1) return ACTION_SPACE;
  return ACTION_GROUP_BASE + 7;                          // group 7 (vbnm)
}

boolean groupPressed(int action)
{
  if (action < ACTION_GROUP_BASE) return false;
  return activeGroup == action - ACTION_GROUP_BASE && !selectionMoved;
}

boolean actionEnabled(int action)
{
  if (action == ACTION_SUGGEST_0) return visibleSuggestions[0].length() > 0;
  if (action == ACTION_SUGGEST_1) return visibleSuggestions[1].length() > 0;
  return true;
}

int homeButtonColor(int action, boolean enabled, boolean isPressed)
{
  if (!enabled)  return color(78);
  if (isPressed) return color(246, 206, 92);
  if (action == ACTION_DELETE)    return color(118);
  if (action == ACTION_SPACE)     return color(175);
  if (action == ACTION_SUGGEST_0 || action == ACTION_SUGGEST_1)
    return color(88, 116, 132);
  return color(90);
}

String actionLabel(int action)
{
  if (action == ACTION_DELETE)    return "del";
  if (action == ACTION_SPACE)     return "space";
  if (action == ACTION_SUGGEST_0) return visibleSuggestions[0];
  if (action == ACTION_SUGGEST_1) return visibleSuggestions[1];
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
  float[] pos = slotPosition(groupLength, index);
  float mx = sizeOfInputArea * 0.18;
  float my = sizeOfInputArea * 0.19;
  return new PVector(
    inputLeft() + mx + (sizeOfInputArea - mx*2) * pos[0],
    inputTop()  + my + (sizeOfInputArea - my*2) * pos[1]);
}

// Slot positions — 3-letter groups use triangle, 4-letter groups use 2×2
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

float previewBoxWidth(int len, float keyWidth)  { return len==4 ? keyWidth*0.30 : keyWidth*0.34; }
float previewBoxHeight(int len, float keyHeight) { return len==4 ? keyHeight*0.28 : keyHeight*0.30; }
float selectionBoxWidth(int len)  { return len==4 ? sizeOfInputArea*0.31 : sizeOfInputArea*0.34; }
float selectionBoxHeight(int len) { return len==4 ? sizeOfInputArea*0.31 : sizeOfInputArea*0.30; }

// ─────────────────────────────────────────────────────────────────────────────
// Language model
// ─────────────────────────────────────────────────────────────────────────────

void loadLanguageModel() { loadFrequencies(); loadBigrams(); }

void loadFrequencies()
{
  String[] lines = loadStrings("ngrams/count_1w.txt");
  for (String line : lines)
  {
    String[] parts = split(line, '\t');
    if (parts.length == 2) wordFreq.put(parts[0].toLowerCase(), int(parts[1]));
  }
}

void loadBigrams()
{
  String[] lines = loadStrings("ngrams/count_2w.txt");
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
    float freebieErrors = lettersExpectedTotal * .05;
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
  float watchscale = DPIofYourDeviceScreen / 138.0;
  pushMatrix();
  translate(width/2, height/2);
  scale(watchscale);
  imageMode(CENTER);
  image(watch, 0, 0);
  popMatrix();
}

//=========SHOULD NOT NEED TO TOUCH THIS METHOD AT ALL!==============
int computeLevenshteinDistance(String phrase1, String phrase2) //this computers error between two strings
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
