require 'net/http'
require 'uri'
require "json"
require 'pp'

$token            = "your_token" # slackAPI用に取得したtoken
$count            = 1000 #slackAPIの取得可能数の限界値。timestampをずらして1000件ずつ取得すれば全件取得できるらしい
$target_name      = nil
$post_channel_name = "post_channnel_name" # 通知対象チャンネル名

def get_reactions_from_user
  p '絵文字使用率を調べたいユーザー名を入力してください。'
  $target_name = gets.chomp!

# SlackAPI：users.list
  res     = Net::HTTP.get(URI.parse("https://slack.com/api/users.list?token=#{$token}&pretty=1"))
  hash    = JSON.parse(res)
  members = hash["members"]

# ユーザー名を知ってればすぐ調べられるようにuserIDとuser名のハッシュを作っておく
  member_lists = {}

  members.each do |member|
    member_lists[member["name"].to_sym] = member["id"]
  end

  if member_lists[$target_name.to_sym].nil?
    puts "該当ユーザーが存在しません"
    return
  end

# 該当ユーザーのIDを取得する
  user_id = member_lists[$target_name.to_sym]

# SlackAPI：reaction.list
  res = Net::HTTP.get(URI.parse("https://slack.com/api/reactions.list?token=#{$token}&count=#{$count}&user=#{user_id}&pretty=1"))

  hash  = JSON.parse(res)
  items = hash["items"]

  messages = []
  items.each do |item|
    messages << item["message"]
  end

  reactions = []
  messages.each do |message|
    reactions << message["reactions"]
  end
  reactions.flatten!
end

def get_reactions_from_channnel
  p '絵文字使用率を調べたいチャンネル名を入力してください。'
  $target_name = gets.chomp!

# チャンネルリスト取得
  res      = Net::HTTP.get(URI.parse("https://slack.com/api/channels.list?token=#{$token}"))
  hash     = JSON.parse(res)
  channels = hash["channels"]

# チャンネル名だけ知ってればすぐ調べられるように、チャンネルIDとチャンネル名のハッシュを作っておく
  channel_lists = {}
  messages      = []

  channels.each do |channel|
    channel_lists[channel["name"].to_sym] = channel["id"]
    messages << channel["messages"]
  end

  if channel_lists[$target_name.to_sym].nil?
    puts "チャンネル名が存在しません"
    return
  end

  channel_id = channel_lists[$target_name.to_sym]
  count      = 1000
  res        = Net::HTTP.get(URI.parse("https://slack.com/api/channels.history?inclusive=true&count=#{$count}&channel=#{channel_id}&token=#{$token}"))

  hash      = JSON.parse(res)
  messages  = hash["messages"]
  reactions = []

  messages.each do |message|
    reactions << message["reactions"]
  end

# 整形
  reactions.compact!.flatten!
end

def post_emoji_ranking(reactions)
#取得したreactionsをランキング化して投稿
# あとでcount数を加算するために初期値0でハッシュを作っておく
  results = Hash.new(0)

  reactions.each do |reaction|
    name                 = reaction["name"]
    results[name.to_sym] += reaction["count"]
  end

# コンソール結果表示用
  puts "#{$target_name}の絵文字使用率ランキング1〜10位"
  result_data = []
  results.sort_by { |_, v| -v }.to_a.first(10).each do |result|
    result_data << result
    puts "#{result[0].to_s.rjust(30, " ")}:#{result[1]}回"
  end

# 該当チャンネルに投稿をするAPIを叩く
  post_api_url = "https://slack.com/api/chat.postMessage"

  uri = URI.parse(post_api_url)
  req = Net::HTTP::Post.new(uri)

# 後でjoinして配列内の文字列を全て結合する
  contents = ["#{$target_name}の絵文字使用率ランキング1〜10位\n"]
  result_data.each.with_index(1) do |data, n|
    contents << "#{n}位　:#{data[0]}:は#{data[1]}回です\n"
  end

  post_data = { token:   "#{$token}",
                channel: "#{$post_channel_name}",
                text:    contents.join, }

  req.set_form_data(post_data)

  req_options = {
    use_ssl: uri.scheme == "https"
  }

  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(req)
  end
end

p '調べたいのはどっち？入力してね　user or channnel　'
target = gets.chomp!

# reactionsを取得
if target == "user"
  reactions = get_reactions_from_user
elsif target == "channnel"
  reactions = get_reactions_from_channnel
else
  puts "user or channnelのどっちかを入力してください"
  return
end

post_emoji_ranking(reactions)