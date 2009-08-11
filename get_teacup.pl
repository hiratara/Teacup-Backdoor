#!/usr/local/bin/perl
use strict;
use warnings;
use Encode qw(from_to);
use WWW::Mechanize;
use Template;

sub get_mech{
my $m = new WWW::Mechanize();
$m->agent_alias( 'Windows IE 6' );
return $m;
}

my $exit_loop = 0;
my $max_process = 30;
my $tempfile    = 'temp.txt';
my $room_logdir = 'room';
my $tpl      = 'moto.tt';
my $disthtml = '/Library/WebServer/Documents/teacup/index.html';
#my $disthtml = 'out.html';

# time��¬
my $s_time = time();

# �����
unlink $tempfile || die $!;

# �����μ���
my $m = get_mech();
$m->get('http://chat.teacup.com/');
my @room_links = $m->find_all_links( 
    url_regex => qr"http://chat\d*\.teacup\.com/chat/r\d+/" );

#my @room_links = ();  #DBUEGDEBUGDEBUG

# SIGTERM �ϥ�ɥ�򥻥å�
$SIG{TERM} = sub { $exit_loop = 1 };

my %pids = ();
foreach my $l(@room_links){
    last if $exit_loop;

    my $url = $l->url_abs();

    next unless $l->text();  #����̾�������ʤ����Ф�

    if(keys %pids >= $max_process){
        # ���äѤ����äѤ��äݤ��ä����Ԥ�
        my $pid = wait();
        delete $pids{$pid};
    }

    if(my $pid = fork() ){
        # �ƥץ���
        $pids{$pid} = 1;
    }elsif(defined $pid){
        # �ҥץ���
        exit(child($l));
    }else{
        die "sorry.";
    }
}

# ���ƽ�λ����Τ��Ԥ�
while( wait() >= 0 ){ }

# ������������
my @room_data = ();
open(IN, '<', $tempfile) || die $!;
while(<IN>){
    chomp;
    my ($url, $name, @mems) = split(/\t/, $_);
    push(@room_data, {
        URL => $url, 
        DISP => $name, 
        MEMBERS => \@mems,
        LOGS => get_roomlogs( get_room_id($url) )
    });
}
close(IN);

@room_data = sort {
    my $anum = get_room_id($a->{URL});
    my $bnum = get_room_id($b->{URL});
    return $anum <=> $bnum;
} @room_data;

# �ƥ�ץ졼�Ȥ˽񤭽Ф�
my $tt = Template->new({});

$tt->process($tpl, {
    PROC_TIME => time() - $s_time,
    UPD_TIME  => scalar(localtime()),
    ROOMS => \@room_data,
}, $disthtml) || die $tt->error();

exit(0);


sub get_room_id{
    $_[0] =~ /r(\d+)/;
    return $1;
}


sub get_roomlogs{
    my $id = shift;
    local *IN;

    my @logs = ();

    open(IN, '<', "$room_logdir/$id") || die;
    while(<IN>){
        chomp;
        my ($name, $comment) = split(/\t/, $_);
        push(@logs, {NAME => $name, COMMENT => $comment});
    }
    close(IN);

    return \@logs;
}


sub split_tag{
    my $html = shift;
    $html =~ s/<[^>]+>//g;
    return $html;
}


sub child{
    my $l = shift;
    local *OUT;

    # SIGTERM �ϥ�ɥ�򥻥å�
    $SIG{TERM} = sub { exit 0 };

    from_to(my $text = $l->text(), 'cp932', 'utf8');
    my $url = $l->url_abs();

    my $c = undef;
    {
        my $m = get_mech;
        $m->get($url);
#warn $m->status;
        $c = $m->content();
        from_to($c, 'cp932', 'utf8');
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

    open(OUT, '>>', $tempfile) || die $!;
    print OUT join("\t", $url, $text, @members), "\n";
    close(OUT);

    my $room_id = get_room_id($url);
    open(OUT, '>', "$room_logdir/$room_id") || die;
    print OUT map {join("\t", @$_), "\n"} @logs;
    close(OUT);

    return 0;
}
