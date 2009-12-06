#!/opt/local/bin/perl
use strict;
use warnings;
use Encode;
use AnyEvent::Impl::Perl;
use Coro::LWP;
use WWW::Mechanize;
use Coro;
use Template;


my $tpl      = 'moto.tt';
my $disthtml = '/Library/WebServer/Documents/teacup/index.html';
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

    die $url
        unless $c =~ m|<TD bgcolor="#E9ECED">&nbsp;(.*)</TD>|;
    my $member  = $1;
    my @members = split(/ ,/, $member);

    my @logs;
    while($c =~ m{^<FONT color="[^\r\n]+?">([^\r\n]+?) </FONT>&gt; ([^\r\n]+?)<FONT color="#737373">\(\d\d/\d\d \w{3} \d\d:\d\d:\d\d\)</FONT><BR>$}smg){
        push(@logs, [split_tag($1), split_tag($2)]);
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
$m->get('http://chat.teacup.com/');
my @room_links = $m->find_all_links( 
    url_regex => qr"http://chat\d*\.teacup\.com/chat(\?r=\d+|/r\d+/)" );

#my @room_links = ();  #DBUEGDEBUGDEBUG

my @coros;
my %results;

foreach my $l(@room_links){
    my $url = $l->url_abs();

    next unless $l->text();  #部屋名が不明なら飛ばす

    push @coros, async {
        $results{$url} = child $l;
    };
}

$_->join for @coros;

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
