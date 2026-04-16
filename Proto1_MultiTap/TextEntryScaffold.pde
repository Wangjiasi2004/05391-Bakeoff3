import java.util.Arrays;
import java.util.Collections;
import java.util.Random;
import java.util.HashMap;

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

// ===== AUTOCOMPLETE =====
HashMap<String, Integer> wordFreq = new HashMap<String, Integer>();
HashMap<String, HashMap<String, Integer>> bigramFreq = new HashMap<>();
String suggestion1 = "";
String suggestion2 = "";

// ===== T9 KEYBOARD =====
String[] t9Keys = {
  "abc", "def", "ghi",
  "jkl", "mno", "pqrs",
  "tuv", "wxyz", "<",
  " "
};

int lastKeyIndex = -1;
int tapIndex = 0;
int lastTapTime = 0;
int tapTimeout = 500;

//Variables for my silly implementation. You can delete this:
char currentLetter = 'a';

//You can modify anything in here. This is just a basic implementation.
void setup()
{
  watch = loadImage("watchhand3smaller.png");
  phrases = loadStrings("phrases2.txt"); //load the phrase set into memory 
  Collections.shuffle(Arrays.asList(phrases), new Random()); //randomize the order of the phrases with no seed
  //Collections.shuffle(Arrays.asList(phrases), new Random(100)); //randomize the order of the phrases with seed 100; same order every time, useful for testing
 
  orientation(LANDSCAPE); //can also be PORTRAIT - sets orientation on android device
  size(800, 800); //Sets the size of the app. You should modify this to your device's native size. Many phones today are 1080 wide by 1920 tall.
  textFont(createFont("Arial", 24)); //set the font to arial 24. Creating fonts is expensive, so make difference sizes once in setup, not draw
  noStroke(); //my code doesn't use any strokes
  
  // Load autocomplete data
  loadFrequencies();
  loadBigrams();
  
  //set finger as cursor. do not change the sizing.
  noCursor();
  mouseCursor = loadImage("finger.png"); //load finger image to use as cursor
  cursorHeight = DPIofYourDeviceScreen * (400.0/250.0); //scale finger cursor proportionally with DPI
  cursorWidth = cursorHeight * 0.6; 
}

//You can modify anything in here. This is just a basic implementation.
void draw()
{
  background(255); //clear background
  drawWatch(); //draw watch background
  
  float x = width/2-sizeOfInputArea/2;
  float y = height/2-sizeOfInputArea/2;
  fill(100);
  rect(x, y, sizeOfInputArea, sizeOfInputArea); //input area should be 1" by 1"

  if (finishTime!=0)
  {
    fill(128);
    textAlign(CENTER);
    text("Finished", 280, 150);
    cursor(ARROW);
    return;
  }

  if (startTime==0 & !mousePressed)
  {
    fill(128);
    textAlign(CENTER);
    text("Click to start time!", 280, 150); //display this messsage until the user clicks!
  }

  if (startTime!=0)
  {
    //feel free to change the size and position of the target/entered phrases and next button 
    textAlign(LEFT); //align the text left
    fill(128);
    text("Phrase " + (currTrialNum+1) + " of " + totalTrialNum, 70, 50); //draw the trial count
    fill(128);
    text("Target:   " + currentPhrase, 70, 100); //draw the target string
    text("Entered:  " + currentTyped +"|", 70, 140); //draw what the user has entered thus far 
    
    //draw very basic next button
    fill(255, 0, 0);
    rect(600, 600, 200, 200); //draw next button
    fill(255);
    text("NEXT > ", 650, 650); //draw next label

    ////my draw code
    //fill(255, 0, 0); //red button
    //rect(width/2-sizeOfInputArea/2, height/2-sizeOfInputArea/2+sizeOfInputArea/2, sizeOfInputArea/2, sizeOfInputArea/2); //draw left red button
    //fill(0, 255, 0); //green button
    //rect(width/2-sizeOfInputArea/2+sizeOfInputArea/2, height/2-sizeOfInputArea/2+sizeOfInputArea/2, sizeOfInputArea/2, sizeOfInputArea/2); //draw right green button
    //textAlign(CENTER);
    //fill(200);
    //text("" + currentLetter, width/2, height/2-sizeOfInputArea/4); //draw current letter
    
    drawSuggestions(x, y);
    drawKeyboard(x, y);
    
    if (lastKeyIndex != -1 && millis() - lastTapTime > tapTimeout)
    {
      commitCurrentLetter();
    }
  }
  
  //draw cursor with middle of the finger nail being the cursor point. do not change this.
  image(mouseCursor, mouseX+cursorWidth/2-cursorWidth/3, mouseY+cursorHeight/2-cursorHeight/5, cursorWidth, cursorHeight); //draw user cursor   
}

void drawKeyboard(float x, float y)
{
  int cols = 3;
  int rows = 4;

  float keyW = sizeOfInputArea / cols;
  float keyH = (sizeOfInputArea * 0.75) / rows;

  float startY = y + sizeOfInputArea * 0.2; // leave space for suggestions only

  textAlign(CENTER, CENTER);
  textSize(16);

  for (int i = 0; i < t9Keys.length; i++)
  {
    int c = i % cols;
    int r = i / cols;

    float kx = x + c * keyW;
    float ky = startY + r * keyH;

    // center space key across bottom row
    if (t9Keys[i].equals(" ")) {
      fill(200);
      rect(x, startY + (rows-1)*keyH, sizeOfInputArea, keyH);
      fill(0);
      text("space", x + sizeOfInputArea/2, startY + (rows-1)*keyH + keyH/2);
      continue;
    }

    fill(200);
    rect(kx, ky, keyW, keyH);

    fill(0);
    String label = t9Keys[i];
    if (label.equals("<")) label = "del";

    text(label, kx + keyW/2, ky + keyH/2);
  }
}

void drawSuggestions(float x, float y)
{
  float boxW = sizeOfInputArea/2;
  float boxH = sizeOfInputArea*0.2;

  textAlign(CENTER, CENTER);
  textSize(14);

  fill(180);
  rect(x, y, boxW, boxH);
  rect(x+boxW, y, boxW, boxH);

  fill(0);
  text(suggestion1, x+boxW/2, y+boxH/2);
  text(suggestion2, x+boxW+boxW/2, y+boxH/2);
}

//my terrible implementation you can entirely replace
boolean didMouseClick(float x, float y, float w, float h) //simple function to do hit testing
{
  return (mouseX > x && mouseX<x+w && mouseY>y && mouseY<y+h); //check to see if it is in button bounds
}

//my terrible implementation you can entirely replace
void mousePressed()
{
  if (startTime == 0)
  {
    nextTrial();
    return;
  }
  
  //if (didMouseClick(width/2-sizeOfInputArea/2, height/2-sizeOfInputArea/2+sizeOfInputArea/2, sizeOfInputArea/2, sizeOfInputArea/2)) //check if click in left button
  //{
  //  currentLetter --;
  //  if (currentLetter<'_') //wrap around to z
  //    currentLetter = 'z';
  //}

  //if (didMouseClick(width/2-sizeOfInputArea/2+sizeOfInputArea/2, height/2-sizeOfInputArea/2+sizeOfInputArea/2, sizeOfInputArea/2, sizeOfInputArea/2)) //check if click in right button
  //{
  //  currentLetter ++;
  //  if (currentLetter>'z') //wrap back to space (aka underscore)
  //    currentLetter = '_';
  //}

  //if (didMouseClick(width/2-sizeOfInputArea/2, height/2-sizeOfInputArea/2, sizeOfInputArea, sizeOfInputArea/2)) //check if click occured in letter area
  //{
  //  if (currentLetter=='_') //if underscore, consider that a space bar
  //    currentTyped+=" ";
  //  else if (currentLetter=='`' & currentTyped.length()>0) //if `, treat that as a delete command
  //    currentTyped = currentTyped.substring(0, currentTyped.length()-1);
  //  else if (currentLetter!='`') //if not any of the above cases, add the current letter to the typed string
  //    currentTyped+=currentLetter;
  //}
  
  float x = width/2-sizeOfInputArea/2;
  float y = height/2-sizeOfInputArea/2;

  // suggestions
  float boxW = sizeOfInputArea/2;
  float boxH = sizeOfInputArea*0.15;

  if (didMouseClick(x, y, boxW, boxH))
    applySuggestion(suggestion1);

  if (didMouseClick(x+boxW, y, boxW, boxH))
    applySuggestion(suggestion2);
   
  
  // ===== T9 KEYBOARD INPUT =====
  int cols = 3;
  int rows = 4;
  
  float keyW = sizeOfInputArea / cols;
  float keyH = (sizeOfInputArea * 0.75) / rows;
  float startY = y + sizeOfInputArea * 0.2;
  
  for (int i = 0; i < t9Keys.length; i++)
  {
    // special case: space bar spans full width
    if (t9Keys[i].equals(" "))
    {
      if (didMouseClick(x, startY + (rows-1)*keyH, sizeOfInputArea, keyH))
      {
        handleT9Key(i);
      }
      continue;
    }
  
    int c = i % cols;
    int r = i / cols;
  
    float kx = x + c * keyW;
    float ky = startY + r * keyH;
  
    if (didMouseClick(kx, ky, keyW, keyH))
    {
      handleT9Key(i);
    }
  }

  //You are allowed to have a next button outside the 1" area
  if (didMouseClick(600, 600, 200, 200)) //check if click is in next button
  {
    nextTrial(); //if so, advance to next trial
  }
}

void handleT9Key(int keyIndex)
{
  String key = t9Keys[keyIndex];

  // SPACE
  if (key.equals(" "))
  {
    commitCurrentLetter();
    currentTyped += " ";
    updateSuggestion();
    return;
  }

  // DELETE
  if (key.equals("<"))
  {
    commitCurrentLetter();
    if (currentTyped.length() > 0)
      currentTyped = currentTyped.substring(0, currentTyped.length()-1);
    updateSuggestion();
    return;
  }

  int now = millis();

  // SAME KEY PRESSED QUICKLY → cycle letters
  if (keyIndex == lastKeyIndex && (now - lastTapTime) < tapTimeout)
  {
    tapIndex = (tapIndex + 1) % key.length();
  }
  else
  {
    commitCurrentLetter();
    lastKeyIndex = keyIndex;
    tapIndex = 0;
  }

  lastTapTime = now;
}

void commitCurrentLetter()
{
  if (lastKeyIndex == -1) return;

  String key = t9Keys[lastKeyIndex];

  if (key.equals(" ") || key.equals("<")) return;

  char letter = key.charAt(tapIndex);
  currentTyped += letter;

  lastKeyIndex = -1;
  tapIndex = 0;

  updateSuggestion();
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum) //check to see if experiment is done
    return; //if so, just return

  if (startTime!=0 && finishTime==0) //in the middle of trials
  {
    System.out.println("==================");
    System.out.println("Phrase " + (currTrialNum+1) + " of " + totalTrialNum); //output
    System.out.println("Target phrase: " + currentPhrase); //output
    System.out.println("Phrase length: " + currentPhrase.length()); //output
    System.out.println("User typed: " + currentTyped); //output
    System.out.println("User typed length: " + currentTyped.length()); //output
    System.out.println("Number of errors: " + computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim())); //trim whitespace and compute errors
    System.out.println("Time taken on this trial: " + (millis()-lastTime)); //output
    System.out.println("Time taken since beginning: " + (millis()-startTime)); //output
    System.out.println("==================");
    lettersExpectedTotal+=currentPhrase.trim().length();
    lettersEnteredTotal+=currentTyped.trim().length();
    errorsTotal+=computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim());
  }

  //probably shouldn't need to modify any of this output / penalty code.
  if (currTrialNum == totalTrialNum-1) //check to see if experiment just finished
  {
    finishTime = millis();
    System.out.println("==================");
    System.out.println("Trials complete!"); //output
    System.out.println("Total time taken: " + (finishTime - startTime)); //output
    System.out.println("Total letters entered: " + lettersEnteredTotal); //output
    System.out.println("Total letters expected: " + lettersExpectedTotal); //output
    System.out.println("Total errors entered: " + errorsTotal); //output

    float wpm = (lettersEnteredTotal/5.0f)/((finishTime - startTime)/60000f); //FYI - 60K is number of milliseconds in minute
    float freebieErrors = lettersExpectedTotal*.05; //no penalty if errors are under 5% of chars
    float penalty = max(errorsTotal-freebieErrors, 0) * .5f;
    
    System.out.println("Raw WPM: " + wpm); //output
    System.out.println("Freebie errors: " + freebieErrors); //output
    System.out.println("Penalty: " + penalty);
    System.out.println("WPM w/ penalty: " + (wpm-penalty)); //yes, minus, becuase higher WPM is better
    System.out.println("==================");

    currTrialNum++; //increment by one so this mesage only appears once when all trials are done
    return;
  }

  if (startTime==0) //first trial starting now
  {
    System.out.println("Trials beginning! Starting timer..."); //output we're done
    startTime = millis(); //start the timer!
  } 
  else
    currTrialNum++; //increment trial number

  lastTime = millis(); //record the time of when this trial ended
  currentTyped = ""; //clear what is currently typed preparing for next trial
  currentPhrase = phrases[currTrialNum]; // load the next phrase!
  //currentPhrase = "abc"; // uncomment this to override the test phrase (useful for debugging)
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


void applySuggestion(String word)
{
  if (word == null || word.length()==0) return;

  String[] parts = split(currentTyped, ' ');
  parts[parts.length-1] = word;

  currentTyped = join(parts, " ") + " ";
  updateSuggestion();
}

void updateSuggestion()
{
  String prefix = getLastWord(currentTyped.toLowerCase());
  String prevWord = getPreviousWord(currentTyped.toLowerCase());

  String best1 = "";
  String best2 = "";
  int f1 = -1;
  int f2 = -1;

  // ===== BIGRAM FIRST =====
  if (bigramFreq.containsKey(prevWord)) {
    HashMap<String, Integer> nextWords = bigramFreq.get(prevWord);

    for (String w : nextWords.keySet()) {
      if (w.startsWith(prefix)) {
        int f = nextWords.get(w);

        if (f > f1) {
          best2 = best1; f2 = f1;
          best1 = w; f1 = f;
        } else if (f > f2) {
          best2 = w; f2 = f;
        }
      }
    }
  }

  // ===== FALLBACK TO UNIGRAM =====
  if (best1.equals("")) {
    for (String w : wordFreq.keySet()) {
      if (w.startsWith(prefix)) {
        int f = wordFreq.get(w);

        if (f > f1) {
          best2 = best1; f2 = f1;
          best1 = w; f1 = f;
        } else if (f > f2) {
          best2 = w; f2 = f;
        }
      }
    }
  }

  suggestion1 = best1;
  suggestion2 = best2;
}

String getPreviousWord(String text)
{
  String[] parts = split(text, ' ');
  if (parts.length < 2) return "";
  return parts[parts.length - 2];
}

String getLastWord(String text)
{
  String[] parts = split(text, ' ');
  if (parts.length == 0) return "";
  return parts[parts.length - 1];
}

void loadFrequencies()
{
  String[] lines = loadStrings("ngrams/count_1w.txt");
  for (String line : lines)
  {
    String[] parts = split(line, '\t');
    if (parts.length == 2)
      wordFreq.put(parts[0].toLowerCase(), int(parts[1]));
  }
}

void loadBigrams() {
  String[] lines = loadStrings("ngrams/count_2w.txt");

  for (String line : lines) {
    String[] parts = split(line, '\t');
    if (parts.length != 2) continue;

    String[] words = split(parts[0].toLowerCase(), ' ');
    if (words.length != 2) continue;

    String first = words[0];
    String second = words[1];
    int freq = int(parts[1]);

    if (!bigramFreq.containsKey(first)) {
      bigramFreq.put(first, new HashMap<String, Integer>());
    }

    bigramFreq.get(first).put(second, freq);
  }
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
