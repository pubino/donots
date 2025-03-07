# Screenshot configuration
SCREENSHOT_WIDTH = 400     # Width of capture area in pixels
SCREENSHOT_HEIGHT = 100    # Height of capture area in pixels
MARGIN_RIGHT = 1200        # Margin from right edge of screen
MARGIN_TOP = 30           # Margin from top edge of screen
NUM_SCREENSHOTS = 1       # Number of screenshots to take per notification
SCREENSHOT_DELAY = 0      # Delay between screenshots in seconds
INITIAL_DELAY = 0         # Delay before taking first screenshot after notification
EMAIL_RECIPIENT = "recipient@example  # Change this to your desired recipient
RECIPIENT_NAME = "Michael Bino"
EMAIL_SUBJECT = "New Notification"
EMAIL_CONTENT = "new notification"
SENDING_ACCOUNT = "sender@example" # Replace with your sending email for cc

import subprocess
import time
from datetime import datetime
import os

def send_email_with_screenshots(screenshots):
    """Sends an email with screenshots as attachments using Apple Mail, CC'ing the sending account."""
    
    # Convert all paths to absolute paths
    screenshots = [os.path.abspath(path) for path in screenshots]
    
    # Create the attachments part of the AppleScript with explicit paths
    attachments = []
    for path in screenshots:
        # Print debugging info about the file
        print(f"Processing attachment: {path}")
        print(f"File exists: {os.path.exists(path)}")
        print(f"File size: {os.path.getsize(path) if os.path.exists(path) else 'N/A'} bytes")
        
        attachments.append(f'''
            set attachmentPath to POSIX file "{path}"
            tell theMessage
                make new attachment with properties {{file name:attachmentPath}} at after last paragraph
            end tell
        ''')
    
    attachments_script = "\n".join(attachments)
    
    # AppleScript to create and send an email with attachments, including CC
    script = f'''
    tell application "Mail"
        set theMessage to make new outgoing message with properties {{visible:true}}
        
        tell theMessage
            set subject to "{EMAIL_SUBJECT}"
            set content to "{EMAIL_CONTENT}"
            make new to recipient at end of to recipients with properties {{name:"{RECIPIENT_NAME}", address:"{EMAIL_RECIPIENT}"}}
            make new cc recipient at end of cc recipients with properties {{address:"{SENDING_ACCOUNT}"}}
            
            # Add each attachment
            {attachments_script}
            
            # Keep the message visible for debugging
            set visible to true
            
            # Optional: delay to see if attachments are added
            delay 1
            
            send
        end tell
    end tell
    '''

    # Print the full script for debugging
    print("\nExecuting AppleScript:")
    print(script)

    # Execute AppleScript
    try:
        process = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        print(f"\nAppleScript Output: {process.stdout}")
        if process.returncode == 0:
            print(f"✅ Email sent to {EMAIL_RECIPIENT} and CC'ed {SENDING_ACCOUNT} with {len(screenshots)} attachments.")
        else:
            print(f"❌ AppleScript Error: {process.stderr.strip()}")
    except Exception as e:
        print(f"❌ Failed to execute AppleScript: {e}")




def run_applescript(script):
    """Executes an AppleScript command and returns the output."""
    try:
        proc = subprocess.Popen(['osascript', '-e', script], 
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE)
        out, err = proc.communicate()
        return out.decode('utf-8').strip()
    except Exception as e:
        print(f"Error running AppleScript: {e}")
        return None

def get_notifications():
    """Checks for notifications in Notification Center."""
    script = '''
    tell application "System Events"
        try
            tell process "Notification Center"
                set notificationList to every UI element of window 1
                if (count of notificationList) > 0 then
                    return "notification_detected"
                end if
            end tell
        end try
    end tell
    '''
    return run_applescript(script)

def get_display_bounds():
    """Get the actual display bounds using AppleScript."""
    script = '''
    tell application "System Events"
        set screenBounds to bounds of window of desktop
        return item 3 of screenBounds & "," & item 4 of screenBounds
    end tell
    '''
    try:
        result = run_applescript(script)
        if result:
            width, height = map(int, result.split(','))
            return width, height
    except Exception as e:
        print(f"Error getting display bounds: {e}")
    return 1280, 800  # fallback values


def take_notification_screenshot():
    """Takes screenshots of the upper right corner of the screen and emails them together."""
    try:
        if not os.path.exists("notification_screenshots"):
            os.makedirs("notification_screenshots")
            print("Created screenshots directory")

        screen_width, screen_height = get_display_bounds()
        print(f"Detected screen bounds: {screen_width}x{screen_height}")

        x = screen_width - SCREENSHOT_WIDTH + MARGIN_RIGHT
        y = MARGIN_TOP

        print(f"Capturing region: x={x}, y={y}, width={SCREENSHOT_WIDTH}, height={SCREENSHOT_HEIGHT}")

        if INITIAL_DELAY > 0:
            print(f"Waiting initial delay of {INITIAL_DELAY} seconds...")
            time.sleep(INITIAL_DELAY)

        screenshots = []
        for i in range(NUM_SCREENSHOTS):
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"notification_screenshots/notification_{timestamp}_{i+1}.png"

            print(f"Attempting to capture screenshot {i+1}/{NUM_SCREENSHOTS} to: {filename}")

            try:
                # Try to capture the specific region first
                result = subprocess.run([
                    "screencapture",
                    "-R", f"{x},{y},{SCREENSHOT_WIDTH},{SCREENSHOT_HEIGHT}",
                    "-x",
                    filename
                ], capture_output=True, text=True)

                if result.stderr:
                    print(f"screencapture command errors: {result.stderr}")

                # If the capture fails due to no intersection with displays, fall back to full screen
                if result.returncode != 0 or not os.path.exists(filename) or os.path.getsize(filename) == 0:
                    print(f"Error or empty screenshot. Falling back to full screen capture.")
                    filename = f"notification_screenshots/notification_full_{timestamp}_{i+1}.png"
                    result = subprocess.run([
                        "screencapture",
                        "-x",  # Capture the entire screen
                        filename
                    ], capture_output=True, text=True)

                # Check if the screenshot was successfully saved
                if os.path.exists(filename) and os.path.getsize(filename) > 0:
                    print(f"Screenshot saved: {filename}")
                    screenshots.append(filename)
                else:
                    print("Error: Screenshot file was not created or is empty")

                if i < NUM_SCREENSHOTS - 1:
                    time.sleep(SCREENSHOT_DELAY)

            except Exception as e:
                print(f"Error taking screenshot {i+1}: {e}")

        # **Send all screenshots in a single email after capturing completes**
        if screenshots:
            print("Screenshots to attach:", screenshots)
            for path in screenshots:
                if not os.path.exists(path):
                    print(f"Error: Screenshot not found - {path}")
                elif os.path.getsize(path) == 0:
                    print(f"Error: Screenshot is empty - {path}")

            print(f"Attempting to send email with {len(screenshots)} attachments")
            send_email_with_screenshots(screenshots)

        return screenshots

    except Exception as e:
        print(f"Error in take_notification_screenshot: {e}")
        return []


def main():
    print("Monitoring for notifications... (Press Ctrl+C to exit)")
    print("Note: You may need to grant accessibility permissions to Terminal/IDE in")
    print("System Settings -> Privacy & Security -> Accessibility")
    print("AND grant screen recording permissions in System Settings -> Privacy & Security -> Screen Recording")
    print(f"Taking {NUM_SCREENSHOTS} screenshot(s) per notification")
    if INITIAL_DELAY > 0:
        print(f"Initial delay: {INITIAL_DELAY} seconds")
    if NUM_SCREENSHOTS > 1:
        print(f"Delay between screenshots: {SCREENSHOT_DELAY} seconds")
    print("Screenshots will be saved in the 'notification_screenshots' directory")
    
    last_check = False
    
    try:
        while True:
            notification_present = get_notifications() == "notification_detected"
            
            if notification_present and not last_check:
                timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                print(f"\n[{timestamp}] New Notification")
                
                # Take screenshots with error handling
                screenshot_paths = take_notification_screenshot()
                if screenshot_paths:
                    print(f"Screenshots captured: {len(screenshot_paths)}")
                    for path in screenshot_paths:
                        print(f"  - {path}")
                else:
                    print("Screenshots failed - check console output above for details")
                print("-" * 50)
            
            last_check = notification_present
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\nStopping notification monitor...")
    except Exception as e:
        print(f"An error occurred: {e}")
        raise

if __name__ == "__main__":
    main()
