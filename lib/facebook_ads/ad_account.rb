# https://developers.facebook.com/docs/marketing-api/reference/ad-account
module FacebookAds
  class AdAccount < Base

    FIELDS = %w(id account_id account_status age created_time currency min_campaign_group_spend_cap min_daily_budget name amount_spent spend_cap balance last_used_time)

    class << self
      def all
        get!('/me/adaccounts', objectify: true)
      end

      def find_by(conditions)
        all.detect do |ad_account|
          conditions.all? do |key, value|
            ad_account.send(key) == value
          end
        end
      end
    end

    # has_many campaigns

    def campaigns(effective_status: ['ACTIVE'], limit: 100)
      FacebookAds::Campaign.paginate!("/#{id}/campaigns", query: { effective_status: effective_status, limit: limit })
    end

    def create_campaign(name:, objective:, status: 'ACTIVE')
      raise Exception, "Objective must be one of: #{FacebookAds::Campaign::OBJECTIVES.to_sentence}" unless FacebookAds::Campaign::OBJECTIVES.include?(objective)
      raise Exception, "Status must be one of: #{FacebookAds::Campaign::STATUSES.to_sentence}" unless FacebookAds::Campaign::STATUSES.include?(status)
      campaign = FacebookAds::Campaign.post!("/#{id}/campaigns", query: { name: name, objective: objective, status: status })
      FacebookAds::Campaign.find(campaign.id)
    end

    # has_many ad_images

    def ad_images(hashes: nil, limit: 100)
      if hashes.present?
        FacebookAds::AdImage.get!("/#{id}/adimages", query: { hashes: hashes }, objectify: true)
      else
        FacebookAds::AdImage.paginate!("/#{id}/adimages", query: { limit: limit })
      end
    end

    def create_ad_images(urls)
      files = urls.collect do |url|
        pathname = Pathname.new(url)
        name = "#{pathname.dirname.basename}.jpg"
        data = self.class.get(url).body
        file = File.open("/tmp/#{name}", 'w') # Assume *nix-based system.
        file.binmode
        file.write(data)
        file.close
        [name, File.open(file.path)]
      end.to_h

      response = FacebookAds::AdImage.post!("/#{id}/adimages", query: files, objectify: false) # detect_mime_type: true
      files.values.each { |file| File.delete(file.path) }

      if response['images'].present?
        hashes = response['images'].map { |key, hash| hash['hash'] }
        ad_images(hashes: hashes)
      else
        []
      end
    end

    # has_many ad_creatives

    def ad_creatives(limit: 100)
      FacebookAds::AdCreative.paginate!("/#{id}/adcreatives", query: { limit: limit })
    end

    def create_ad_creative(creative, carousel: true)
      optional = %i(instagram_actor_id)

      required = if carousel
        %i(name page_id link message assets call_to_action_type multi_share_optimized multi_share_end_card)
      else
        %i(name page_id message link link_title image_hash call_to_action_type)
      end

      if (keys = required - creative.keys).present?
        raise Exception, "Creative is missing the following: #{keys.to_sentence}"
      end

      raise Exception, "Creative call_to_action_type must be one of: #{FacebookAds::AdCreative::CALL_TO_ACTION_TYPES.to_sentence}" unless FacebookAds::AdCreative::CALL_TO_ACTION_TYPES.include?(creative[:call_to_action_type])

      query = if carousel
        FacebookAds::AdCreative.carousel(creative)
      else
        FacebookAds::AdCreative.photo(creative)
      end

      creative = FacebookAds::AdCreative.post!("/#{id}/adcreatives", query: query) # Returns a FacebookAds::AdCreative instance.
      FacebookAds::AdCreative.find(creative.id)
    end

    # has_many ad_insights

    def ad_insights(range: Date.today..Date.today)
      campaigns.map do |campaign|
        campaign.ad_insights(range: range)
      end.flatten
    end

  end
end
