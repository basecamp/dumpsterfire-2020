require 'mail'
require 'base64'

class DumpsterMail

  def initialize(raw_email)
    @raw = raw_email
    @mail = Mail.read_from_string(@raw)
  end

  # For debugging
  def mail
    @mail
  end

  def from
    mail.from.first
  end

  def is_hey?
    case
    when from =~ /@hey\.com$/
      true
    when from =~ /@basecamp.com$/
      true
    else
      false
    end
  end

  def subject
    mail.subject
  end

  def valid?
    text? || has_attachment?
  end

  def text?
    @mail.text? || !@mail.text_part.nil?
  end

  def has_attachment?
    @mail.has_attachments? && @mail.attachments[0].content_type.start_with?('image/')
  end

  def attachment
    @mail.attachments[0].decoded
  end

  def text
    @mail.text? ? @mail.decoded : @mail.text_part.decoded
  end

  def content_type
    if has_attachment?
      @mail.attachments[0].content_type
    elsif @mail.multipart?
      @mail.text_part.content_type
    else
      @mail.content_type
    end
  end

  def render
    Base64.encode64(has_attachment? ? attachment : text)
  end
end
