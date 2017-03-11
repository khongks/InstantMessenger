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

// Enum for two Sections
// CreateNewChannelSection: Includes a form for adding new channels.
// CurrentChannelsSection: Shows a list of channels.
enum Section: Int {
  case createNewChannelSection = 0
  case currentChannelsSection
}

class ChannelListViewController: UITableViewController {
  
  // Store the sender name
  var senderDisplayName: String?
  // Add a text field
  var newChannelTextField: UITextField?
  // An array of channel objects to store the channel
  private var channels: [Channel] = []
  // Used to store a reference to the list of channels in the database
  private lazy var channelRef: FIRDatabaseReference = FIRDatabase.database().reference().child("channels")
  // channelRefHandle will hold a handle to the reference so you can remove it later on.
  private var channelRefHandle: FIRDatabaseHandle?
  
  
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "All Channels"
    // Query the Firebase database and get a list of channels to show in your table view.
    observeChannels()
  }
  
  deinit {
    if let refHandle = channelRefHandle {
      channelRef.removeObserver(withHandle: refHandle)
    }
  }
  
  // Set 2 sections
  override func numberOfSections(in tableView: UITableView) -> Int {
    return 2
  }
  
  // Set the number of rows for each section.
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if let currentSection: Section = Section(rawValue: section) {
      switch currentSection {
      case .createNewChannelSection:
        return 1  // Always 1
      case .currentChannelsSection:
        return channels.count // Number of channels
      }
    } else {
      return 0
    }
  }
  
  // Define what goes in each cell.
  // Section1: you store the text field from the cell in your newChannelTextField property.
  // Section2: you just set the cell’s text label as your channel name
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let reuseIdentifier = (indexPath as NSIndexPath).section == Section.createNewChannelSection.rawValue ? "NewChannel" : "ExistingChannel"
    
    let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier, for: indexPath)
    
    if (indexPath as NSIndexPath).section == Section.createNewChannelSection.rawValue {
      if let createNewChannelCell = cell as? CreateChannelCell {
        newChannelTextField = createNewChannelCell.newChannelNameField
      }
    } else if (indexPath as NSIndexPath).section == Section.currentChannelsSection.rawValue {
      cell.textLabel?.text = channels[(indexPath as NSIndexPath).row].name
    }
    return cell
  }
  
  
  // Go to show the channel when tapped
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    if indexPath.section == Section.currentChannelsSection.rawValue {
      let channel = channels[(indexPath as NSIndexPath).row]
      self.performSegue(withIdentifier: "ShowChannel", sender: channel)
    }
  }
  
  // Enable delete
  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    return true
  }
  
  // Implement deleting channel
  override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
    if (editingStyle == UITableViewCellEditingStyle.delete) {
      channelRef.child(channels[indexPath.row].id).removeValue(completionBlock: {
        (error, ref) in
        if let error = error {
          print(error.localizedDescription)
        } else {
          //self.channels.remove(at: indexPath.row)
          //self.tableView.reloadData()
          //channelRef.child(channels[indexPath.row].id).removeAllObservers()
        }
      })
    }
  }
  
  // Query the Firebase database and get a list of channels to show in your table view.
  private func observeChannels() {
    // Use the observe method to listen for new channels being written to the Firebase DB
    // Store a handle to the reference
    channelRefHandle = channelRef.observe(.childAdded, with: { (snapshot) -> Void in
      // Receives a snapshot which contains the data and other helf methods
      let channelData = snapshot.value as! Dictionary<String, AnyObject>
      let id = snapshot.key
      // Pull the data out of the snapshot and, if OK; create a Channel model & add to your channels array.
      if let name = channelData["name"] as! String!, name.characters.count > 0 {
        self.channels.append(Channel(id: id, name: name))
        self.tableView.reloadData()
      } else {
        print("Error! Could not decode channel data")
      }
    })
    
    channelRefHandle = channelRef.observe(.childRemoved, with: { (snapshot) ->  Void in
      let channelData = snapshot.value as! Dictionary<String, AnyObject>
      let id = snapshot.key
      
      if let name = channelData["name"] as! String!, name.characters.count > 0 {
        var i: Int = 0;
        for channel in self.channels {
          if channel.id == id {
            self.channels.remove(at: i)
          }
          i += 1
        }
        self.tableView.reloadData()
      } else {
        print("Error! Could not decode channel data")
      }
    })
  }
  
  // Used to create channel, when Create Channel Button is tapped
  @IBAction func createChannel(_ sender: Any) {
    // Check if you have a channel name in the text field.
    if let name = newChannelTextField?.text {
      if name != "" {
        // Create a new channel reference with a unique key using childByAutoId().
        let newChannelRef = channelRef.childByAutoId()
        // Create a dictionary to hold the data for this channel.
        // A [String: AnyObject] works as a JSON-like object.
        let channelItem = [
          "name": name
        ]
        // Set the name on this new channel, which is saved to Firebase automatically!
        newChannelRef.setValue(channelItem)
        newChannelTextField?.text = ""
      }
    }
  }
  
  // Set initial values for senderId and senderDisplayName, app can uniquely identify the sender
  // Before going to ChatViewController
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    super.prepare(for: segue, sender: sender)
    
    if let channel = sender as? Channel {
      let chatViewController = segue.destination as! ChatViewController
      
      chatViewController.senderDisplayName = senderDisplayName
      chatViewController.channel = channel
      chatViewController.channelRef = channelRef.child(channel.id)
    }
  }
}
