require 'shellwords'

module ReceiptOcr
  PIX_AMOUNT_PATTERNS = [
    /R\$\s*([0-9]+[.,][0-9]{2})/,
    /(?:Valor|valor|R\$)[:\s]*([0-9]+[.,][0-9]{2})/,
    /([0-9]+[.,][0-9]{2})\s*(?:reais|R\$)/,
  ].freeze

  PIX_SENDER_PATTERNS = [
    /(?:de|De|DE)[:\s]+([A-Za-zÀ-ÖØ-öø-ÿ]+(?:\s+[A-Za-zÀ-ÖØ-öø-ÿ]+){1,3})/,
    /(?:enviado\s*por|Enviado\s*por|remetente|Remetente)[:\s]+([A-Za-zÀ-ÖØ-öø-ÿ]+(?:\s+[A-Za-zÀ-ÖØ-öø-ÿ]+){1,3})/,
    /(?:pagador|Pagador)[:\s]+([A-Za-zÀ-ÖØ-öø-ÿ]+(?:\s+[A-Za-zÀ-ÖØ-öø-ÿ]+){1,3})/,
  ].freeze

  def self.extract_text(image_path)
    return '' unless File.exist?(image_path)
    text = `tesseract #{image_path.shellescape} stdout -l por --psm 6 2>/dev/null`.strip
    text.force_encoding('UTF-8').scrub
  end

  def self.extract_amount(text)
    text.scan(/R\$\s*([0-9]+[.,][0-9]{2})/).each do |match|
      return match[0].sub(',', '.').to_f
    end
    text.scan(/([0-9]+[.,][0-9]{2})\s*(?:reais|R\$)/).each do |match|
      return match[0].sub(',', '.').to_f
    end
    text.scan(/R\$([0-9]{2,6})/).each do |match|
      v = match[0]
      if v.length >= 4
        cents = v[-2..-1]
        reais = v[0...-2]
        return "#{reais}.#{cents}".to_f
      end
    end
    nil
  end

  def self.extract_sender(text)
    patterns = [
      /(?:de|De|DE)[:\s]+([A-Za-zÀ-ÖØ-öø-ÿ]+(?:\s+[A-Za-zÀ-ÖØ-öø-ÿ]+){1,3})/,
      /(?:enviado\s*por|Enviado\s*por|remetente|Remetente|pagador|Pagador)[:\s]+([A-Za-zÀ-ÖØ-öø-ÿ]+(?:\s+[A-Za-zÀ-ÖØ-öø-ÿ]+){1,3})/,
      /(?:origem|Origem)[:\s]+([A-Za-zÀ-ÖØ-öø-ÿ]+(?:\s+[A-Za-zÀ-ÖØ-öø-ÿ]+){1,3})/,
    ]
    patterns.each do |pat|
      m = text.match(pat)
      return m[1].strip.split("\n").first.strip if m
    end
    clean = text.gsub("\n", " ")
    names = clean.scan(/([A-ZÀ-Ö][a-zà-öø-ÿ]+(?:\s+[A-ZÀ-Ö][a-zà-öø-ÿ]+){1,3})/)
    names.each do |name|
      candidate = name[0].strip
      next if candidate.length < 5 || %w[Voce Recebido Transferencia Pagamento Comprovante Valor Protocolo].include?(candidate.split.first)
      return candidate
    end
    nil
  end

  def self.process(image_path)
    text = extract_text(image_path)
    {
      raw_text: text,
      amount: extract_amount(text),
      sender: extract_sender(text),
      ocr_ok: !text.empty?
    }
  end

  def self.match_payment?(ocr_data, payment)
    return false unless ocr_data[:amount]
    expected = payment[:amount].to_s.sub(',', '.').to_f
    (ocr_data[:amount] - expected).abs < 0.01
  end
end
