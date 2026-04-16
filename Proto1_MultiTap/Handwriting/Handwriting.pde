import net.sourceforge.tess4j.*; // Import the Tess4J library
import java.io.File;

Tesseract tesseract;
String recognizedText = "Draw something and press 'R'";

void setup() {
  size(600, 400);
  background(255);
  
  // Initialize Tesseract
  tesseract = new Tesseract();
  
  // Set the path to the 'tessdata' folder in your sketch directory
  tesseract.setDatapath(sketchPath("tessdata"));
}

void draw() {
  // UI and Instructions
  fill(0);
  noStroke();
  rect(0, 0, width, 50);
  fill(255);
  textAlign(CENTER, CENTER);
  text(recognizedText, width/2, 25);
  
  // Drawing logic
  if (mousePressed) {
    stroke(0);
    strokeWeight(10);
    line(pmouseX, pmouseY, mouseX, mouseY);
  }
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    // 1. Save only the drawing area (skipping the UI bar)
    PImage drawing = get(0, 50, width, height - 50);
    drawing.save("output.png");
    
    // 2. Perform OCR
    try {
      File imageFile = new File(sketchPath("output.png"));
      recognizedText = "Reading...";
      
      // Recognition happens here
      String result = tesseract.doOCR(imageFile);
      recognizedText = "I see: " + result.trim();
    } catch (TesseractException e) {
      recognizedText = "Error: " + e.getMessage();
      e.printStackTrace();
    }
  }
  
  if (key == 'c' || key == 'C') {
    background(255);
    recognizedText = "Cleared! Draw again.";
  }
}
