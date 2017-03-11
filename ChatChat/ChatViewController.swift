/*
 * Copyright (c) 2015 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import Firebase
import JSQMessagesViewController
import Photos

// Sublcass JSQMessagesViewController, from UIViewController
final class ChatViewController: JSQMessagesViewController {
  
  // Holds the reference of the channel in the Firebase Database
  var channelRef: FIRDatabaseReference?
  var channel: Channel? {
    didSet {
      title = channel?.name
    }
  }
  
  // Array to store the various instances
  var messages = [JSQMessage]()
  
  // Declare incoming/outgoing bubbles
  lazy var outgoingBubbleImageView: JSQMessagesBubbleImage = self.setupOutgoingBubble()
  lazy var incomingBubbleImageView: JSQMessagesBubbleImage = self.setupIncomingBubble()
  
  // Hold the reference of the messages in the Firebase Database
  private lazy var messageRef: FIRDatabaseReference = self.channelRef!.child("messages")
  private var newMessageRefHandle: FIRDatabaseHandle?
  
  // Create a Firebase reference that tracks whether the local user is typing.
  private lazy var userIsTypingRef: FIRDatabaseReference
    = self.channelRef!.child("typingIndicator").child(self.senderId)
  
  // Store whether the local user is typing in a private property.
  private var localTyping = false
  
  // Use a computed property to update localTyping and userIsTypingRef each time it’s changed.
  var isTyping: Bool {
    get {
      return localTyping
    }
    set {
      localTyping = newValue
      userIsTypingRef.setValue(newValue)
    }
  }
  
  // Firebase storage reference, same as the Firebase database references but for a storage object
  lazy var storageRef: FIRStorageReference
    = FIRStorage.storage().reference(forURL: "gs://chatchat-2f983.appspot.com/")
  
  // Firebase query to  retrieve all of the users that are currently typing.
  private lazy var usersTypingQuery: FIRDatabaseQuery
    = self.channelRef!.child("typingIndicator").queryOrderedByValue().queryEqual(toValue: true)
  
  // Dummy URL
  private let imageURLNotSetKey = "NOTSET"
  
  private var photoMessageMap = [String: JSQPhotoMediaItem]()
  
  private var updatedMessageRefHandle: FIRDatabaseHandle?
  
  // MARK: View Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    // Sets the senderId based on the logged in Firebase user.
    self.senderId = FIRAuth.auth()?.currentUser?.uid
    
    // Disable avatars
    collectionView!.collectionViewLayout.incomingAvatarViewSize = CGSize.zero
    collectionView!.collectionViewLayout.outgoingAvatarViewSize = CGSize.zero
    
    // Call this method to observe messages
    observeMessages()
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    
    // Call this method to observe typing
    observeTyping()
  }
  
  // Housekeeping
  deinit {
    if let refHandle = newMessageRefHandle {
      messageRef.removeObserver(withHandle: refHandle)
    }
    
    if let refHandle = updatedMessageRefHandle {
      messageRef.removeObserver(withHandle: refHandle)
    }
  }
  
  // Returns to populate the rows with messages data
  override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageDataForItemAt indexPath: IndexPath!) -> JSQMessageData! {
    return messages[indexPath.item]
  }
  
  // Return the number of items in each section; in this case, the number of messages.
  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return messages.count
  }
  
  // Set the colored bubble image for each message
  override func collectionView(_ collectionView: JSQMessagesCollectionView!, messageBubbleImageDataForItemAt indexPath: IndexPath!) -> JSQMessageBubbleImageDataSource! {
    // Get the message
    let message = messages[indexPath.item]
    if message.senderId == senderId { // If sent by the local user, return the outgoing image view.
      return outgoingBubbleImageView
    } else { //Otherwise, return the incoming image view.
      return incomingBubbleImageView
    }
  }
  
  // Disable avatars
  override func collectionView(_ collectionView: JSQMessagesCollectionView!, avatarImageDataForItemAt indexPath: IndexPath!) -> JSQMessageAvatarImageDataSource! {
    return nil
  }
  
  // Set the text color
  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = super.collectionView(collectionView, cellForItemAt: indexPath) as! JSQMessagesCollectionViewCell
    
    let message = messages[indexPath.item]
    if message.senderId == senderId {
      cell.textView?.textColor = UIColor.white
    } else {
      cell.textView?.textColor = UIColor.black
    }
    return cell
  }
  
  // Create a messasge and adds to the datasource
  private func addMessage(withId id: String, name: String, text: String) {
    if let message = JSQMessage(senderId: id, displayName: name, text: text) {
      messages.append(message)
    }
  }

  // Called to observe any messages added in Firebase database
  private func observeMessages() {
    messageRef = channelRef!.child("messages")
    // Create a query that limits the synchronization to the last 25 messages.
    let messageQuery = messageRef.queryLimited(toLast:25)
    
    // Use the observe method to listen for new messages written to the Firebase DB. 
    // Use the .ChildAdded event to observe for every child item that has been added, and will be added, at the messages location.
    newMessageRefHandle = messageQuery.observe(.childAdded, with: { (snapshot) -> Void in
      // Extract the messageData from the snapshot.
      let messageData = snapshot.value as! Dictionary<String, String>
      if let id = messageData["senderId"] as String!, let name = messageData["senderName"] as String!, let text = messageData["text"] as String!, text.characters.count > 0 {
        
        // Call addMessage(withId:name:text) to add the new message to the data source
        self.addMessage(withId: id, name: name, text: text)
        // Inform JSQMessagesViewController that a message has been received.
        self.finishReceivingMessage()
        if name != self.senderDisplayName {
          JSQSystemSoundPlayer.jsq_playMessageReceivedSound()
        }
      } else if let id = messageData["senderId"] as String!,
        // First, check to see if you have a photoURL set.
        let photoURL = messageData["photoURL"] as String! {
        // If so, create a new JSQPhotoMediaItem. This object encapsulates rich media in messages — exactly what you need here!
        if let mediaItem = JSQPhotoMediaItem(maskAsOutgoing: id == self.senderId) {
          // With that media item, call addPhotoMessage
          self.addPhotoMessage(withId: id, key: snapshot.key, mediaItem: mediaItem)
          // Finally, check to make sure the photoURL contains the prefix for a Firebase Storage object. If so, fetch the image data
          if photoURL.hasPrefix("gs://") {
            self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: nil)
          }
        }

      } else {
        print("Error! Could not decode message data")
      }
    })
    
    
    // We can also use the observer method to listen for
    // changes to existing messages.
    // We use this to be notified when a photo has been stored
    // to the Firebase Storage, so we can update the message data
    updatedMessageRefHandle = messageRef.observe(.childChanged, with: { (snapshot) in
      let key = snapshot.key
      let messageData = snapshot.value as! Dictionary<String, String> // 1
      
      if let photoURL = messageData["photoURL"] as String! { // 2
        // The photo has been updated.
        if let mediaItem = self.photoMessageMap[key] { // 3
          self.fetchImageDataAtURL(photoURL, forMediaItem: mediaItem, clearsPhotoMessageMapOnSuccessForKey: key) // 4
        }
      }
    })
  }
  
  // Called to observe any typing happening
  // Creates a child reference to your channel called typingIndicator, which is where you’ll update the typing status of the user. You don’t want this data to linger around after users have logged out, so you can delete it once the user has left using onDisconnectRemoveValue().
  private func observeTyping() {
    let typingIndicatorRef = channelRef!.child("typingIndicator")
    userIsTypingRef = typingIndicatorRef.child(senderId)
    userIsTypingRef.onDisconnectRemoveValue()
    
    // Observe
    
    // You observe for changes using .value; this will call the completion block anytime it changes.
    usersTypingQuery.observe(.value) { (data: FIRDataSnapshot) in
      
      // You need to see how many users are in the query. If the there’s just one user and that’s the local user, don’t display the indicator.
      if data.childrenCount == 1 && self.isTyping {
        return
      }
      
      // At this point, if there are users, it’s safe to set the indicator. Call scrollToBottomAnimated(animated:) to ensure the indicator is displayed.
      self.showTypingIndicator = data.childrenCount > 0
      self.scrollToBottom(animated: true)
    }
  }
  
  // Setup outgoing bubble
  private func setupOutgoingBubble() -> JSQMessagesBubbleImage {
    let bubbleImageFactory = JSQMessagesBubbleImageFactory()
    return bubbleImageFactory!.outgoingMessagesBubbleImage(with: UIColor.jsq_messageBubbleBlue())
  }
  
  // Setup incoming bubble
  private func setupIncomingBubble() -> JSQMessagesBubbleImage {
    let bubbleImageFactory = JSQMessagesBubbleImageFactory()
    return bubbleImageFactory!.incomingMessagesBubbleImage(with: UIColor.jsq_messageBubbleGreen())
  }
  
  // When Send button is pressed, save the message into Firebase database
  override func didPressSend(_ button: UIButton!, withMessageText text: String!, senderId: String!, senderDisplayName: String!, date: Date!) {
    // Using childByAutoId(), you create a child reference with a unique key.
    let itemRef = messageRef.childByAutoId()
    // Create a dictionary to represent the message.
    let messageItem = [
      "senderId": senderId!,
      "senderName": senderDisplayName!,
      "text": text!,
      ]
    // Save the value at the new child location.
    itemRef.setValue(messageItem)
    // You then play the canonical “message sent” sound.
    JSQSystemSoundPlayer.jsq_playMessageSentSound()
    // Complete the “send” action and reset the input toolbar to empty.
    finishSendingMessage()
    // Resets the local typing indicator
    isTyping = false
  }
  
  // Method to send photo
  func sendPhotoMessage() -> String? {
    let itemRef = messageRef.childByAutoId()
    let messageItem = [
      "photoURL": imageURLNotSetKey,
      "senderId": senderId!,
      ]
    itemRef.setValue(messageItem)
    JSQSystemSoundPlayer.jsq_playMessageSentSound()
    finishSendingMessage()
    return itemRef.key
  }
  
  // Update the message once you get the Firebase object URL for the image
  func setImageURL(_ url: String, forPhotoMessageWithKey key: String) {
    let itemRef = messageRef.child(key)
    itemRef.updateChildValues(["photoURL": url])
  }
  
  // Sibling method to addMessage(withId:name:text:)
  private func addPhotoMessage(withId id: String, key: String, mediaItem: JSQPhotoMediaItem) {
    if let message = JSQMessage(senderId: id, displayName: "", media: mediaItem) {
      messages.append(message)
      
      if (mediaItem.image == nil) {
        photoMessageMap[key] = mediaItem
      }
      collectionView.reloadData()
    }
  }

  // Fetch the image data from Firebase Storage to display
  private func fetchImageDataAtURL(_ photoURL: String, forMediaItem mediaItem: JSQPhotoMediaItem,   clearsPhotoMessageMapOnSuccessForKey key: String?) {
    // Get a reference to the stored image.
    let storageRef = FIRStorage.storage().reference(forURL: photoURL)
    // Get the image data from the storage.
    storageRef.data(withMaxSize: INT64_MAX){ (data, error) in
      if let error = error {
        print("Error downloading image data: \(error)")
        return
      }
      // Get the image metadata from the storage.
      storageRef.metadata(completion: { (metadata, metadataErr) in
        if let error = metadataErr {
          print("Error downloading metadata: \(error)")
          return
        }
        
        // If the metadata suggests that the image is a GIF you use a category on UIImage that was pulled in via the SwiftGifOrigin Cocapod. This is needed because UIImage doesn’t handle GIF images out of the box. Otherwise you just use UIImage in the normal fashion.
        if (metadata?.contentType == "image/gif") {
          mediaItem.image = UIImage.gifWithData(data!)
        } else {
          mediaItem.image = UIImage.init(data: data!)
        }
        self.collectionView.reloadData()
        
        // Finally, you remove the key from your photoMessageMap now that you’ve fetched the image data.
        guard key != nil else {
          return
        }
        self.photoMessageMap.removeValue(forKey: key!)
      })
    }
  }
  
  // To detect that user is typing
  override func textViewDidChange(_ textView: UITextView) {
    super.textViewDidChange(textView)
    // If the text is not empty, the user is typing
    isTyping = textView.text != ""
  }
  
  // Implement the method that handles selection of Photo
  override func didPressAccessoryButton(_ sender: UIButton!) {
    let picker = UIImagePickerController()
    picker.delegate = self
    if (UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera)) {
      picker.sourceType = UIImagePickerControllerSourceType.camera
    } else {
      picker.sourceType = UIImagePickerControllerSourceType.photoLibrary
    }
    present(picker, animated: true, completion:nil)
  }
  
  
  override func collectionView(_ collectionView: JSQMessagesCollectionView!, layout collectionViewLayout: JSQMessagesCollectionViewFlowLayout!, heightForMessageBubbleTopLabelAt indexPath: IndexPath!) -> CGFloat {
    let data = self.collectionView(self.collectionView, messageDataForItemAt: indexPath)
    if (self.senderId == data?.senderDisplayName()) {
      return 0.0
    }
    return kJSQMessagesCollectionViewCellLabelHeightDefault
  }
  
  // Display sender name
  override func collectionView(_ collectionView: JSQMessagesCollectionView!, attributedTextForMessageBubbleTopLabelAt indexPath: IndexPath!) -> NSAttributedString! {
    let message = messages[indexPath.item]
    switch message.senderId {
    case self.senderId:
      return nil
    default:
      guard let senderDisplayName = message.senderDisplayName else {
        assertionFailure()
        return nil
      }
      return NSAttributedString(string: senderDisplayName)
    }
  }
}


// Implement the UIImagePickerControllerDelegate methods to handle when the user picks the image.
extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController,
                             didFinishPickingMediaWithInfo info: [String : Any]) {
    
    picker.dismiss(animated: true, completion:nil)
    
    // Check to see photo URL is present in the info dictionary. If so, you know you have a photo from the library.
    if let photoReferenceUrl = info[UIImagePickerControllerReferenceURL] as? URL {
      // Handle picking a Photo from the Photo Library
      
      // Pull the PHAsset from the photo URL
      let assets = PHAsset.fetchAssets(withALAssetURLs: [photoReferenceUrl], options: nil)
      let asset = assets.firstObject
      
      // Call sendPhotoMessage and receive the Firebase key.
      if let key = sendPhotoMessage() {
        
        // Get the file URL for the image.
        asset?.requestContentEditingInput(with: nil, completionHandler: { (contentEditingInput, info) in
          let imageFileURL = contentEditingInput?.fullSizeImageURL
          
          // Create a unique path based on the user’s unique ID and the current time.
          let path = "\(FIRAuth.auth()?.currentUser?.uid)/\(Int(Date.timeIntervalSinceReferenceDate * 1000))/\(photoReferenceUrl.lastPathComponent)"
          
          // Save the image file to Firebase Storage
          self.storageRef.child(path).putFile(imageFileURL!, metadata: nil) { (metadata, error) in
            if let error = error {
              print("Error uploading photo: \(error.localizedDescription)")
              return
            }
            // Once the image has been saved, you call setImageURL() to update your photo message with the correct URL
            self.setImageURL(self.storageRef.child((metadata?.path)!).description, forPhotoMessageWithKey: key)
          }
        })
      }
    } else {
      // Grab the image from the info dictionary.
      let image = info[UIImagePickerControllerOriginalImage] as! UIImage
      
      // Call your sendPhotoMessage() method to save the fake image URL to Firebase.
      if let key = sendPhotoMessage() {
        
        // Get a JPEG representation of the photo, ready to be sent to Firebase storage.
        let imageData = UIImageJPEGRepresentation(image, 1.0)
        
        // Create a unique URL based on the user’s unique id and the current time.
        let imagePath = FIRAuth.auth()!.currentUser!.uid + "/\(Int(Date.timeIntervalSinceReferenceDate * 1000)).jpg"
        
        // Create a FIRStorageMetadata object and set the metadata to image/jpeg.
        let metadata = FIRStorageMetadata()
        metadata.contentType = "image/jpeg"
        
        // Save the photo to Firebase Storage
        storageRef.child(imagePath).put(imageData!, metadata: metadata) { (metadata, error) in
          if let error = error {
            print("Error uploading photo: \(error)")
            return
          }
          // 7. Once the image has been saved, you call setImageURL() again.
          self.setImageURL(self.storageRef.child((metadata?.path)!).description, forPhotoMessageWithKey: key)
        }
      }
    }
  }
  
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true, completion:nil)
  }
}
