require 'sequel'

module DbStore
  DB_URL = ENV['DATABASE_URL'] || 'postgres://rubymc:RUBYMCJAVA2026@localhost/rubymc'

  def self.db
    @db ||= Sequel.connect(DB_URL)
  end

  def self.connected?
    db.test_connection
  rescue
    false
  end

  # ── Users ──────────────────────────────────────────────

  def self.upsert_user(discord_id, username: nil, avatar_url: nil, role: 'user')
    existing = db[:users].where(discord_id: discord_id).first
    if existing
      updates = { updated_at: Time.now }
      updates[:username] = username if username
      updates[:avatar_url] = avatar_url if avatar_url
      updates[:role] = role if role
      db[:users].where(discord_id: discord_id).update(updates)
      db[:users].where(discord_id: discord_id).first
    else
      db[:users].insert(
        discord_id: discord_id,
        username: username,
        avatar_url: avatar_url,
        role: role,
        created_at: Time.now,
        updated_at: Time.now
      )
      db[:users].where(discord_id: discord_id).first
    end
  end

  def self.find_user(discord_id)
    db[:users].where(discord_id: discord_id).first
  end

  def self.all_users
    db[:users].order(:username).all
  end

  # ── Payments ────────────────────────────────────────────

  def self.create_payment(attrs)
    now = Time.now
    db[:payments].insert({
      id: attrs[:id],
      user_id: attrs[:user_id],
      plan_id: attrs[:plan],
      plan_label: attrs[:plan_label],
      amount: attrs[:amount].to_s.sub(',', '.').to_f,
      status: attrs[:status] || 'pending',
      pix_code: attrs[:pix_code],
      created_at: now
    })
    db[:payments].where(id: attrs[:id]).first
  end

  def self.find_payment(payment_id)
    db[:payments].where(id: payment_id).first
  end

  def self.pending_payments
    db[:payments].where(status: 'pending').order(Sequel.desc(:created_at)).all
  end

  def self.all_payments
    db[:payments].order(Sequel.desc(:created_at)).all
  end

  def self.user_payments(discord_id)
    user = find_user(discord_id)
    return [] unless user
    db[:payments].where(user_id: user[:id]).order(Sequel.desc(:created_at)).all
  end

  def self.confirm_payment(payment_id, confirmed_by:)
    payment = db[:payments].where(id: payment_id).first
    return nil unless payment
    now = Time.now
    db[:payments].where(id: payment_id).update(
      status: 'completed',
      confirmed_by: confirmed_by,
      confirmed_at: now
    )
    db[:payments].where(id: payment_id).first
  end

  def self.reject_payment(payment_id, rejected_by:)
    payment = db[:payments].where(id: payment_id).first
    return nil unless payment
    now = Time.now
    db[:payments].where(id: payment_id).update(
      status: 'rejected',
      rejected_by: rejected_by,
      rejected_at: now
    )
    db[:payments].where(id: payment_id).first
  end

  def self.attach_receipt(payment_id, receipt_path:, receipt_ext:, ocr_amount: nil, ocr_sender: nil, ocr_raw: nil)
    updates = {
      receipt_path: receipt_path,
      receipt_ext: receipt_ext,
      ocr_amount: ocr_amount,
      ocr_sender: ocr_sender
    }
    db[:payments].where(id: payment_id).update(updates)
    db[:payments].where(id: payment_id).first
  end

  # ── Active Memberships ──────────────────────────────────

  def self.set_active_membership(user_id, plan_id:, plan_label:, expires_at: nil)
    db[:active_memberships].where(user_id: user_id).delete
    db[:active_memberships].insert(
      user_id: user_id,
      plan_id: plan_id,
      plan_label: plan_label,
      expires_at: expires_at,
      role_granted: false,
      created_at: Time.now,
      updated_at: Time.now
    )
    db[:active_memberships].where(user_id: user_id).first
  end

  def self.get_active_membership(user_id)
    db[:active_memberships].where(user_id: user_id).first
  end

  def self.clear_active_membership(user_id)
    db[:active_memberships].where(user_id: user_id).delete
  end

  # ── Import from encrypted file ──────────────────────────

  def self.import_from_vip_data(data)
    return 0 unless data && data[:payments].is_a?(Array)
    imported = 0
    data[:payments].each do |p|
      user_id = nil
      if p[:user_id]
        user = find_user(p[:user_id])
        user_id = user[:id] if user
      end
      existing = db[:payments].where(id: p[:id]).first
      next if existing

      db[:payments].insert(
        id: p[:id],
        user_id: user_id,
        plan_id: p[:plan],
        plan_label: p[:plan_label],
        amount: p[:amount].to_s.sub(',', '.').to_f,
        status: p[:status] || 'completed',
        pix_code: p[:pix_code],
        receipt_path: p[:receipt],
        receipt_ext: p[:receipt_ext],
        ocr_amount: p[:ocr_amount],
        ocr_sender: p[:ocr_sender],
        confirmed_by: p[:confirmed_by],
        confirmed_at: p[:confirmed_at] ? Time.parse(p[:confirmed_at]) : nil,
        rejected_by: p[:rejected_by],
        rejected_at: p[:rejected_at] ? Time.parse(p[:rejected_at]) : nil,
        created_at: p[:created_at] ? Time.parse(p[:created_at]) : Time.now
      )
      imported += 1
    end

    data[:pending_payments]&.each do |p|
      user_id = nil
      if p[:user_id]
        user = find_user(p[:user_id])
        user_id = user[:id] if user
      end
      existing = db[:payments].where(id: p[:id]).first
      next if existing

      db[:payments].insert(
        id: p[:id],
        user_id: user_id,
        plan_id: p[:plan],
        plan_label: p[:plan_label],
        amount: p[:amount].to_s.sub(',', '.').to_f,
        status: p[:status] || 'pending',
        pix_code: p[:pix_code],
        receipt_path: p[:receipt],
        receipt_ext: p[:receipt_ext],
        ocr_amount: p[:ocr_amount],
        ocr_sender: p[:ocr_sender],
        created_at: p[:created_at] ? Time.parse(p[:created_at]) : Time.now
      )
      imported += 1
    end

    imported
  end
end
