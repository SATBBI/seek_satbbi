class ContactRequestMessageLog < MessageLog

  default_scope { where(message_type: CONTACT_REQUEST) }
  scope :pending_requests, ->(projects) { where(subject: projects).pending }

  # message logs created since the recent period, for that person and interested item
  scope :recent_requests, ->(person, item) {
    where(subject: item).where(sender: person).recent
  }

  # records a contact request for a sender and item, along with any details provided
  def self.log_request(sender, item, details)
    ContactRequestMessageLog.create(subject: item, sender: sender, details: details)
  end
end