#!/usr/bin/env perl
use strict;
use warnings;
use Encode;
use Coro::LWP;
use WWW::Mechanize;
use Web::Scraper;
use Coro;
use Coro::Semaphore;
use Template;


my $tpl      = 'moto.tt';
my $disthtml = '/var/www/teacup/index.html';
$disthtml = 'out.html' if $ENV{DEBUG};


sub get_mech{
    my $m = new WWW::Mechanize();
    $m->agent_alias( 'Windows IE 6' );
    return $m;
}


sub split_tag{
    my $html = shift;
    $html =~ s/<[^>]+>//g;
    return $html;
}


my $scraper = scraper {
	process '#name_list', members => 'TEXT';
	process '.log_line1', 'logs[]' => 'TEXT';
};
sub child{
    my $l = shift;

    my $text = encode_utf8 $l->text;
    my $url = $l->url_abs();

    my $c = undef;
    {
        my $m = get_mech;
        $m->get($url);
#warn $m->status;
        $c = encode_utf8 $m->content;
#warn $c;
    }

    my $parsed = $scraper->scrape( \$c );

    ( my $members = $parsed->{members} || '' ) =~ s/^\xa0//;  # remove &nbsp;
    my @members = split(/, /, $members);

    my @logs;
    for( @{ $parsed->{logs} } ){
        m/^(.+) > (.*)\([^)]+\)$/ or warn $_;
        push( @logs, { NAME => split_tag($1), COMMENT => split_tag($2) } );
    }


    return {
        url     => $url,
        text    => $text,
        members => \@members,
        logs    => \@logs,
    };
}


# time計測
my $s_time = time();

# 部屋の取得
my $m = get_mech();
$m->get('http://chat.teacup.com/roomlink.html');
my @room_links = $m->find_all_links( 
    url_regex => qr"http://chat\d*\.teacup\.com/chat(\?r=\d+|/r\d+/)" );

#my @room_links = ();  #DBUEGDEBUGDEBUG

my @coros;
my %results;

my $lock = Coro::Semaphore->new(100);  # 最大同時接続数
my $done = Coro::Semaphore->new;
foreach my $l(@room_links){
    my $url = $l->url_abs();

    next unless $l->text();  #部屋名が不明なら飛ばす

    $done->adjust(-1);
    push @coros, async {
        my $guard = $lock->guard;
        $results{$url} = child $l;
        $done->up;  # notify that the task was done
    };
}

$done->down;  # wait until all tasks was done.

# 部屋情報を収集
my @room_data;
for ( @room_links ){
    my $ret = $results{ $_->url_abs };
    push @room_data, {
        URL     => $ret->{url}, 
        DISP    => $ret->{text}, 
        MEMBERS => $ret->{members},
        LOGS    => $ret->{logs},
    };
}

# テンプレートに書き出し
my $tt = Template->new({});

$tt->process($tpl, {
    PROC_TIME => time() - $s_time,
    UPD_TIME  => scalar(localtime()),
    ROOMS => \@room_data,
}, $disthtml) || die $tt->error();

exit(0);
