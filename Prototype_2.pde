import java.io.BufferedReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Random;

// Set the DPI to make your smartwatch 1 inch square. Measure it on the screen
final int DPIofYourDeviceScreen = 150;

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

// Autocomplete prototype: big grouped keys, fullscreen letter picker, and
// two large suggestion buttons powered only by n-gram corpora.
final String[] GROUPS = {
  "abc", "def", "ghi",
  "jkl", "mno",
  "pqrs", "tuv", "wxyz"
};

final int ACTION_NONE = 0;
final int ACTION_DELETE = 1;
final int ACTION_SPACE = 2;
final int ACTION_SUGGEST_0 = 3;
final int ACTION_SUGGEST_1 = 4;
final int ACTION_GROUP_BASE = 100;

final int SUGGESTION_SLOTS = 2;
final int BUCKET_CAPACITY = 6;
final int PREFIX_LIMIT = 12;
final int MAX_UNIGRAM_WORDS = 60000;

HashMap<String, SuggestionBucket> prefixSuggestions = new HashMap<String, SuggestionBucket>();
HashMap<String, SuggestionBucket> nextWordSuggestions = new HashMap<String, SuggestionBucket>();
String[] visibleSuggestions = {"", ""};
String[] defaultSuggestions = {"the", "and"};

int activeGroup = -1;
int activeTapAction = ACTION_NONE;
boolean selectionMoved = false;
float pressX = 0;
float pressY = 0;
float dragX = 0;
float dragY = 0;

void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt");
  Collections.shuffle(Arrays.asList(phrases), new Random());
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
  {
    nextTrial();
  }

  if (startTime != 0)
  {
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
      int action = homeActionAt(row, col);
      float x = homeCellLeft(col) + buttonInset();
      float y = homeCellTop(row) + buttonInset();
      float w = homeCellWidth() - buttonInset() * 2;
      float h = homeCellHeight() - buttonInset() * 2;
      String label = actionLabel(action);
      boolean enabled = actionEnabled(action);
      boolean isPressed = action == activeTapAction || groupPressed(action);

      fill(homeButtonColor(action, enabled, isPressed));
      rect(x, y, w, h, 10);

      if (action >= ACTION_GROUP_BASE)
      {
        drawGroupPreview(action - ACTION_GROUP_BASE, x, y, w, h, isPressed);
      }
      else
      {
        fill(enabled ? (isPressed ? color(20) : color(248)) : color(170));
        textSize(labelSize(label));
        text(drawLabel(label), x + w / 2, y + h / 2 + 1);
      }
    }
  }
}

void drawSelectionMode()
{
  String group = GROUPS[activeGroup];
  int hoveredIndex = selectionMoved ? activeLetterIndex() : -1;

  textAlign(CENTER, CENTER);

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot = selectionSlotCenter(group.length(), i);
    float boxWidth = selectionBoxWidth(group.length());
    float boxHeight = selectionBoxHeight(group.length());
    boolean isHovered = i == hoveredIndex;

    fill(isHovered ? color(246, 206, 92) : color(95));
    rect(slot.x - boxWidth / 2, slot.y - boxHeight / 2, boxWidth, boxHeight, 14);

    fill(isHovered ? color(20) : color(248));
    textSize(group.length() == 4 ? 34 : 38);
    text(group.charAt(i), slot.x, slot.y + 1);
  }

  fill(250);
  textSize(9);
  text("hold " + group + " and slide to its spot", inputCenterX(), inputTop() + sizeOfInputArea - 8);
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

  refreshVisibleSuggestions();
  pressX = mouseX;
  pressY = mouseY;
  dragX = mouseX;
  dragY = mouseY;
  selectionMoved = false;
  activeTapAction = ACTION_NONE;
  activeGroup = -1;

  int action = actionAt(mouseX, mouseY);
  if (action >= ACTION_GROUP_BASE)
    activeGroup = action - ACTION_GROUP_BASE;
  else
    activeTapAction = action;
}

void mouseDragged()
{
  if (activeTapAction == ACTION_NONE && activeGroup < 0)
    return;

  dragX = constrain(mouseX, inputLeft(), inputLeft() + sizeOfInputArea);
  dragY = constrain(mouseY, inputTop(), inputTop() + sizeOfInputArea);
  if (dist(pressX, pressY, dragX, dragY) > 8)
    selectionMoved = true;
}

void mouseReleased()
{
  if (activeTapAction == ACTION_NONE && activeGroup < 0)
    return;

  dragX = constrain(mouseX, inputLeft(), inputLeft() + sizeOfInputArea);
  dragY = constrain(mouseY, inputTop(), inputTop() + sizeOfInputArea);

  if (activeGroup >= 0)
    handleLetterRelease();
  else
    handleTapRelease();

  activeTapAction = ACTION_NONE;
  activeGroup = -1;
  selectionMoved = false;
}

void handleTapRelease()
{
  int releasedAction = actionAt(dragX, dragY);
  if (releasedAction != activeTapAction)
    return;

  if (activeTapAction == ACTION_DELETE)
  {
    if (currentTyped.length() > 0)
      currentTyped = currentTyped.substring(0, currentTyped.length() - 1);
    return;
  }

  if (activeTapAction == ACTION_SPACE)
  {
    currentTyped += " ";
    return;
  }

  if (activeTapAction == ACTION_SUGGEST_0 || activeTapAction == ACTION_SUGGEST_1)
  {
    int suggestionIndex = activeTapAction - ACTION_SUGGEST_0;
    if (suggestionIndex >= 0 && suggestionIndex < visibleSuggestions.length)
      applySuggestion(visibleSuggestions[suggestionIndex]);
  }
}

void handleLetterRelease()
{
  if (!selectionMoved)
    return;

  int letterIndex = activeLetterIndex();
  currentTyped += GROUPS[activeGroup].charAt(letterIndex);
}

void applySuggestion(String suggestionWord)
{
  if (suggestionWord == null || suggestionWord.length() == 0)
    return;

  String prefix = currentWordPrefix();
  if (prefix.length() > 0)
  {
    int lastSpace = currentTyped.lastIndexOf(' ');
    String base = lastSpace >= 0 ? currentTyped.substring(0, lastSpace + 1) : "";
    currentTyped = base + suggestionWord + " ";
  }
  else
  {
    currentTyped += suggestionWord + " ";
  }
}

void refreshVisibleSuggestions()
{
  String[] next = computeVisibleSuggestions();
  for (int i = 0; i < SUGGESTION_SLOTS; i++)
    visibleSuggestions[i] = next[i];
}

String[] computeVisibleSuggestions()
{
  String[] next = {"", ""};
  String prefix = currentWordPrefix();
  String previousWord = previousContextWord();

  if (prefix.length() > 0)
  {
    if (previousWord.length() > 0)
      fillFromBucket(next, nextWordSuggestions.get(previousWord), prefix);
    fillFromBucket(next, prefixSuggestions.get(prefix), prefix);
    return next;
  }

  if (previousWord.length() > 0)
    fillFromBucket(next, nextWordSuggestions.get(previousWord), "");

  fillWithDefaults(next);
  return next;
}

void fillFromBucket(String[] target, SuggestionBucket bucket, String requiredPrefix)
{
  if (bucket == null)
    return;

  for (int i = 0; i < bucket.words.length; i++)
  {
    String candidate = bucket.words[i];
    if (candidate == null)
      continue;
    if (requiredPrefix.length() > 0 && !candidate.startsWith(requiredPrefix))
      continue;
    addSuggestion(target, candidate);
  }
}

void fillWithDefaults(String[] target)
{
  for (int i = 0; i < defaultSuggestions.length; i++)
    addSuggestion(target, defaultSuggestions[i]);
}

void addSuggestion(String[] target, String candidate)
{
  if (candidate == null || candidate.length() == 0)
    return;

  for (int i = 0; i < target.length; i++)
  {
    if (candidate.equals(target[i]))
      return;
  }

  for (int i = 0; i < target.length; i++)
  {
    if (target[i].length() == 0)
    {
      target[i] = candidate;
      return;
    }
  }
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

int activeLetterIndex()
{
  String group = GROUPS[activeGroup];
  int bestIndex = 0;
  float bestDistance = Float.MAX_VALUE;

  for (int i = 0; i < group.length(); i++)
  {
    PVector slot = selectionSlotCenter(group.length(), i);
    float distance = dist(dragX, dragY, slot.x, slot.y);
    if (distance < bestDistance)
    {
      bestDistance = distance;
      bestIndex = i;
    }
  }

  return bestIndex;
}

int actionAt(float x, float y)
{
  int row = constrain((int)((y - inputTop()) / homeCellHeight()), 0, 3);
  int col = constrain((int)((x - inputLeft()) / homeCellWidth()), 0, 2);
  return homeActionAt(row, col);
}

int homeActionAt(int row, int col)
{
  if (row == 0)
  {
    if (col == 0)
      return ACTION_DELETE;
    if (col == 1)
      return ACTION_SUGGEST_0;
    return ACTION_SUGGEST_1;
  }

  if (row == 1)
    return ACTION_GROUP_BASE + col;

  if (row == 2)
  {
    if (col == 1)
      return ACTION_SPACE;
    return ACTION_GROUP_BASE + (col == 0 ? 3 : 4);
  }

  return ACTION_GROUP_BASE + (col + 5);
}

boolean groupPressed(int action)
{
  if (action < ACTION_GROUP_BASE)
    return false;
  return activeGroup == action - ACTION_GROUP_BASE && !selectionMoved;
}

boolean actionEnabled(int action)
{
  if (action == ACTION_SUGGEST_0)
    return visibleSuggestions[0].length() > 0;
  if (action == ACTION_SUGGEST_1)
    return visibleSuggestions[1].length() > 0;
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
  if (action == ACTION_SUGGEST_0 || action == ACTION_SUGGEST_1)
    return color(88, 116, 132);
  return color(90);
}

String actionLabel(int action)
{
  if (action == ACTION_DELETE)
    return "del";
  if (action == ACTION_SPACE)
    return "space";
  if (action == ACTION_SUGGEST_0)
    return visibleSuggestions[0];
  if (action == ACTION_SUGGEST_1)
    return visibleSuggestions[1];
  return GROUPS[action - ACTION_GROUP_BASE];
}

String drawLabel(String label)
{
  if (label == null || label.length() == 0)
    return " ";

  if (label.length() <= 8)
    return label;

  return label.substring(0, 8);
}

float labelSize(String label)
{
  if (label == null)
    return 11;
  if (label.length() <= 4)
    return 13;
  if (label.length() <= 8)
    return 10;
  return 9;
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

float homeCellWidth()
{
  return sizeOfInputArea / 3.0;
}

float homeCellHeight()
{
  return sizeOfInputArea / 4.0;
}

float homeCellLeft(int col)
{
  return inputLeft() + col * homeCellWidth();
}

float homeCellTop(int row)
{
  return inputTop() + row * homeCellHeight();
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
    textSize(group.length() == 4 ? 13 : 14);
    text(group.charAt(i), slot.x, slot.y + 1);
  }
}

PVector previewSlotCenter(int groupLength, int index, float x, float y, float w, float h)
{
  float[] pos = slotPosition(groupLength, index);
  return new PVector(x + w * pos[0], y + h * pos[1]);
}

PVector selectionSlotCenter(int groupLength, int index)
{
  float[] pos = slotPosition(groupLength, index);
  float marginX = sizeOfInputArea * 0.18;
  float marginY = sizeOfInputArea * 0.19;
  return new PVector(inputLeft() + marginX + (sizeOfInputArea - marginX * 2) * pos[0], inputTop() + marginY + (sizeOfInputArea - marginY * 2) * pos[1]);
}

float[] slotPosition(int groupLength, int index)
{
  if (groupLength == 4)
  {
    if (index == 0)
      return new float[] {0.28, 0.28};
    if (index == 1)
      return new float[] {0.72, 0.28};
    if (index == 2)
      return new float[] {0.28, 0.72};
    return new float[] {0.72, 0.72};
  }

  if (index == 0)
    return new float[] {0.28, 0.32};
  if (index == 1)
    return new float[] {0.72, 0.32};
  return new float[] {0.50, 0.74};
}

float previewBoxWidth(int groupLength, float keyWidth)
{
  return groupLength == 4 ? keyWidth * 0.30 : keyWidth * 0.34;
}

float previewBoxHeight(int groupLength, float keyHeight)
{
  return groupLength == 4 ? keyHeight * 0.28 : keyHeight * 0.30;
}

float selectionBoxWidth(int groupLength)
{
  return groupLength == 4 ? sizeOfInputArea * 0.31 : sizeOfInputArea * 0.34;
}

float selectionBoxHeight(int groupLength)
{
  return groupLength == 4 ? sizeOfInputArea * 0.31 : sizeOfInputArea * 0.30;
}

void loadLanguageModel()
{
  println("Loading autocomplete n-grams...");
  loadPrefixSuggestions();
  loadNextWordSuggestions();
  println("Loaded " + prefixSuggestions.size() + " prefix buckets and " + nextWordSuggestions.size() + " next-word buckets.");
}

void loadPrefixSuggestions()
{
  BufferedReader reader = createReader("count_1w.txt");
  String line = null;
  int loadedWords = 0;

  try
  {
    while ((line = reader.readLine()) != null && loadedWords < MAX_UNIGRAM_WORDS)
    {
      int tab = line.lastIndexOf('\t');
      if (tab <= 0)
        continue;

      String word = line.substring(0, tab).trim().toLowerCase();
      if (!isLowerAlphaWord(word))
        continue;

      long count = parseLongSafe(line.substring(tab + 1));
      if (count <= 0)
        continue;

      int maxPrefix = min(PREFIX_LIMIT, word.length());
      for (int len = 1; len <= maxPrefix; len++)
        bucketFor(prefixSuggestions, word.substring(0, len)).consider(word, count);

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
    try
    {
      if (reader != null)
        reader.close();
    }
    catch (Exception e)
    {
    }
  }
}

void loadNextWordSuggestions()
{
  BufferedReader reader = createReader("count_2w.txt");
  String line = null;

  try
  {
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

      long count = parseLongSafe(line.substring(tab + 1));
      if (count <= 0)
        continue;

      bucketFor(nextWordSuggestions, first).consider(second, count);
    }
  }
  catch (Exception e)
  {
    println("Could not load count_2w.txt");
    e.printStackTrace();
  }
  finally
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
}

SuggestionBucket bucketFor(HashMap<String, SuggestionBucket> map, String key)
{
  SuggestionBucket bucket = map.get(key);
  if (bucket == null)
  {
    bucket = new SuggestionBucket();
    map.put(key, bucket);
  }
  return bucket;
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

void nextTrial()
{
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

class SuggestionBucket
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
