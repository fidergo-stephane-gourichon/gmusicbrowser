# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin LYRICS
Lyrics
Lyrics plugin
Display lyrics of the current song using lyrc.com.ar
=cut

package GMB::Plugin::LYRICS;
use strict;
use warnings;
require 'simple_http.pm';
use base 'Gtk2::VBox';
use constant
{	OPT	=> 'PLUGIN_LYRICS_', # MUST begin by PLUGIN_ followed by the plugin ID / package name
	title	=> _"Lyrics",
};

::SetDefaultOptions(OPT, FontSize => 10, PathFile => "~/.lyrics/%a/%t.lyric", LyricSite => 'lyrc');

my %sites=	# id => [name,url,?post?,function]	if the function return 1 => lyrics can be saved
(	#lyrc	=>	['lyrc','http://lyrc.com.ar/en/tema1en.php','artist=%a&songname=%s'],
	lyrc	=>	['lyrc','http://lyrc.com.ar/en/tema1en.php?artist=%a&songname=%s',undef,sub
		{	local $_=$_[0];
			return -1 if m#<a href=[^>]+add[^>]+>(?:[^<]*</?[b-z]\w*)*[^<]*Add a lyric.(?:[^<]*</?[b-z]\w*)*[^<]*</a>#i;
			return 1 if s#<a href="\#"[^>]+badsong[^>]+>BADSONG</a>##i;
			return 0;
		}],
	#leoslyrics =>	['leolyrics','http://api.leoslyrics.com/api_search.php?artist=%a&songtitle=%s'],
	#google	=>	['google','http://www.google.com/search?q="%a"+"%s"'],
	#googlemusic =>	['google music','http://www.google.com/musicsearch?q="%a"+"%s"'],
	lyriki	=>	['lyriki','http://lyriki.com/index.php?title=%a:%s',undef,
		sub { my $no= $_[0]=~m/<div class="noarticletext">/s; $_[0]=~s/^.*<!--\s*start content\s*-->(.*?)<!--\s*end content\s*-->.*$/$1/s && !$no; }],
	lyricsplugin => [lyricsplugin => 'http://www.lyricsplugin.com/winamp03/plugin/?title=%s&artist=%a',undef,
			sub { my $ok=$_[0]=~m#<div id="lyrics">.*\w\n.*\w.*</div>#s; $_[0]=~s/<div id="admin".*$//s if $ok; return $ok; }],
	lyricssongs =>	['lyrics-songs','http://www.lyrics-songs.com/winamp.php?musica=%s&artista=%a',undef,
			sub { $_[0]=~s#<img src='p_bg2.gif'[^/]*/>##si; return 0 }], #remove image, return always 0 as lyrics-songs sometimes guess when the song is not found
	#lyricwiki =>	[lyricwiki => 'http://lyricwiki.org/%a:%s'], # s#<div id="lyric">(.+?)</div>#$1#
	lyricwikiapi => [lyricwiki => 'http://lyricwiki.org/api.php?artist=%a&song=%s&fmt=html',undef,
		sub { $_[0]!~m#<pre>\W*Not found\W*</pre>#s }],
	#azlyrics => [ azlyrics => 'http://search.azlyrics.com/cgi-bin/azseek.cgi?q="%a"+"%s"'],
);



sub Start
{	GMB::Context::AddPackage(__PACKAGE__,'Lyrics');
}
sub Stop
{	GMB::Context::RemovePackage('Lyrics');
}

sub new
{	my ($class,$widget_options)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;
	$self->{widget_options}=$widget_options;
	my $textview=Gtk2::TextView->new;
	$textview->signal_connect(button_release_event	=> \&button_release_cb);
	$textview->signal_connect(motion_notify_event 	=> \&update_cursor_cb);
	$textview->signal_connect(visibility_notify_event=>\&update_cursor_cb);
	$textview->signal_connect(scroll_event		=> \&scroll_cb);
	$textview->signal_connect(populate_popup	=> \&populate_popup_cb);
	$textview->set_wrap_mode('word');
	$textview->set_left_margin(5);
	$self->{buffer}=$textview->get_buffer;
	$self->{textview}=$textview;
	my $sw=Gtk2::ScrolledWindow->new;
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);
	my $toolbar=Gtk2::Toolbar->new;
	for my $aref
	(	[backb => 'gtk-go-back',\&Back_cb,	_"Previous page"],
		[saveb => 'gtk-save',	\&Save_text,	_"Save",	_"Save lyrics"],
		[undef, 'gtk-refresh',	\&Refresh_cb,	_"Refresh"],
	)
	{	my ($key,$stock,$cb,$label,$tip)=@$aref;
		my $item=Gtk2::ToolButton->new_from_stock($stock);
		$item->set_label($label);
		$item->signal_connect(clicked => $cb);
		$item->set_tooltip($::Tooltips,$tip,'') if $tip;
		$toolbar->insert($item,-1);
		$self->{$key}=$item if $key;
	}
	$self->{saveb}->set_is_important(1);
	my $zoom=Gtk2::ToolItem->new;
	$zoom->add( ::NewPrefSpinButton( OPT.'FontSize', sub {SetFont($textview)},1,0,4,50,1,5) );
	$zoom->set_tooltip($::Tooltips,_"Font size",'');
	my $source=::NewPrefCombo( OPT.'LyricSite', {map {$_=>$sites{$_}[0]} keys %sites} ,cb => \&SetSource, toolitem=> _"Lyrics source");
	my $scroll=::NewPrefCheckButton( OPT.'AutoScroll', _"Auto-scroll",\&SetAutoScroll,_"Scroll with the song",undef,1);
	$toolbar->insert($_,-1) for $zoom,$scroll,$source;

	$self->pack_start($toolbar,0,0,0);
	$self->add($sw);
	$self->show_all;
	$toolbar->set_no_show_all(1);
	$toolbar->hide if $self->{widget_options}{HideToolbar};
	$self->{toolbar}=$toolbar;
	$self->signal_connect(destroy => \&destroy_event_cb);

	$self->{buffer}->signal_connect(modified_changed => sub {$_[1]->set_sensitive($_[0]->get_modified);}, $self->{saveb});
	$self->{backb}->set_sensitive(0);
	SetFont($textview);
	$self->SetAutoScroll;

	return $self;
}
sub destroy_event_cb
{	my $self=shift;
	$self->cancel;
}

sub cancel
{	my $self=shift;
	delete $::ToDo{'8_lyrics'.$self};
	$self->{waiting}->abort if $self->{waiting};
	$self->{waiting}=$self->{pixtoload}=undef;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $entry=::NewPrefEntry(OPT.'PathFile' => _"Load/Save lyrics in :");
	my $preview= Label::Preview->new(\&filename_preview, 'SongID Option',undef,1);
	#$preview->set_alignment(0,.5);
	my $autosave=::NewPrefCheckButton(OPT.'AutoSave' => _"Auto-save positive finds",undef,_"only works with some lyrics source and when the lyrics tab is displayed");
	my $Bopen=Gtk2::Button->new(_"open context window");
	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	$vbox->pack_start($_,::FALSE,::FALSE,1) for $entry,$preview,$autosave,$Bopen;
	return $vbox;
}

sub filename_preview
{	return '' unless defined $::SongID;
	my $t=::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
	$t= $t ? ::PangoEsc(_"example : ".$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
	return '<small>'.$t.'</small>';
}

sub SetAutoScroll
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	if ($self->{AutoScroll}=$::Options{OPT.'AutoScroll'})
		{ ::Watch($self,Time => \&TimeChanged); }
	else	{ ::UnWatch($self,'Time'); };
}
sub SetFont
{	my $textview=$_[0];
	$textview->modify_font(Gtk2::Pango::FontDescription->from_string($::Options{OPT.'FontSize'}));
}

sub SetSource
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	$self->SongChanged($self->{ID},1);
}

sub Back_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $url=pop @{$self->{history}};
	$_[0]->set_sensitive(0) unless @{$self->{history}};
	$self->{lastokurl}=undef;
	$self->load_url($url) if $url;
}
sub Refresh_cb
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $ID=delete $self->{ID};
	$self->SongChanged($ID,1);
}

sub SongChanged
{	my ($self,$ID,$force)=@_;
	return unless defined $ID;
	return if defined $self->{ID} && $ID==$self->{ID} && !$force;
	$self->{ID}=$ID;
	$self->{time}=undef;

	if (!$force)
	{	my $file=::pathfilefromformat( $self->{ID}, $::Options{OPT.'PathFile'}, undef,1 );
		if ($file && -r $file)
		{	::IdleDo('8_lyrics'.$self,1000,\&load_file,$self,$file);
			return
		}
	}

	my ($title,$artist)= map ::url_escapeall($_), Songs::Get($ID,qw/title artist/);
	my (undef,$url,$post,$check)=@{$sites{$::Options{OPT.'LyricSite'}}};
	for ($url,$post) { next unless defined $_; s/%a/$artist/; s/%s/$title/; }
	#$self->load_url($url,$post);
	::IdleDo('8_lyrics'.$self,1000,\&load_url,$self,$url,$post,$check);
}

sub TimeChanged		#scroll the text
{	my $self=$_[0];
	return unless defined $::SongID && defined $self->{ID} && $self->{ID} eq $::SongID;
	return unless defined $::PlayTime;
	my $adj=($self->get_children)[1]->get_vadjustment;
	my $range=($adj->upper - $adj->lower - $adj->page_size);
	return unless $range >0;
	return if $adj->get_value > $adj->upper - $adj->page_size;
	my $delta=$::PlayTime - ($self->{time} || 0);
	return if $delta <1;
	my $inc=$delta / Songs::Get($::SongID,'length');
	$self->{time}=$::PlayTime;
	$adj->set_value($adj->get_value+$inc*$range);
}

sub populate_popup_cb
{	my ($textview,$menu)=@_;
	my $self=::find_ancestor($textview,__PACKAGE__);

	my $item0=Gtk2::CheckMenuItem->new(_"Scroll with song");
	$item0->set_active(1) if $self->{AutoScroll};
	$item0->signal_connect(toggled => sub
		{	my $self=$_[1];
			$::Options{OPT.'AutoScroll'}=$_[0]->get_active;
			$self->SetAutoScroll;
		},$self);

	my $item1=Gtk2::CheckMenuItem->new(_"Hide toolbar");
	$item1->set_active(1) if $self->{widget_options}{HideToolbar};
	$item1->signal_connect(toggled => sub
		{	my $self=$_[1];
			if ($self->{widget_options}{HideToolbar}^=1)	{$self->{toolbar}->hide}
			else						{$self->{toolbar}->show}
		},$self);
	$menu->append($_) for Gtk2::SeparatorMenuItem->new, $item0,$item1;

	# add menu items for links
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$textview->get_pointer);
	if (my $url=$self->url_at_coords($x,$y))
	{	my $item2=Gtk2::MenuItem->new(_"Open link in Browser");
		$item2->signal_connect(activate => sub	{ ::openurl($url); });
		my $item3=Gtk2::MenuItem->new(_"Copy link address");
		$item3->signal_connect(activate => sub
		{	my $url=$_[1];
			my $clipboard=$_[0]->get_clipboard(Gtk2::Gdk::Atom->new('CLIPBOARD',1));
			$clipboard->set_text($url);
		},$url);
		$menu->prepend($_) for Gtk2::SeparatorMenuItem->new, $item3,$item2;
	}

	$menu->show_all;
}

sub load_url
{	my ($self,$url,$post,$check)=@_;
	$self->{buffer}->set_text(_"Loading...");
	$self->{buffer}->set_modified(0);
	$self->cancel;
	warn "lyrics : loading $url\n";# if $::debug;
	$self->{url}=$url;
	$self->{post}=$post;
	$self->{check}=$check; # function to check if lyrics found
	$self->{waiting}=Simple_http::get_with_cb(cb => sub {$self->loaded(@_)},url => $url,post => $post);
}

sub loaded #_very_ crude html to gtktextview renderer
{	my ($self,$data,$type,$url)=@_;
	delete $self->{waiting};
	my $buffer=$self->{buffer};
	unless ($data) { $data=_("Loading failed.").qq( <a href="$self->{url}">)._("retry").'</a>'; $type="text/html"; }
	$self->{url}=$url if $url; #for redirections
	$buffer->delete($buffer->get_bounds);
	my $encoding;
	if ($type && $type=~m#^text/.*; ?charset=([\w-]+)#) {$encoding=$1}
	if ($type && $type!~m#^text/html#)
	{	if	($type=~m#^text/#)	{$buffer->set_text($data);}
		elsif	($type=~m#^image/#)
		{	my $loader=::LoadPixData($data);
			if (my $p=$loader->get_pixbuf) {$buffer->insert_pixbuf(0,$p);}
		}
		return;
	}
	$encoding=$1 if $data=~m#<meta *http-equiv="Content-Type" *content="text/html; charset=([\w-]+)"#;
	$encoding='cp1252' if $encoding && $encoding eq 'iso-8859-1'; #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding||='cp1252'; #default encoding
	$data=Encode::decode($encoding,$data) if $encoding;

	my $oklyrics;
	$oklyrics= $self->{check}($data) if $self->{check};
#print "$data\n";
	if ($self->{lastokurl})
	{	my $history=$self->{history}||=[];
		push @$history,$self->{lastokurl};
		$#$history=20 if $#$history>20;
		$self->{backb}->set_sensitive(1) if @$history==1;
	}
	$self->{lastokurl}=$self->{url};

	for ($data)
	{s/<!--.*?-->//gs;
	 s#<noscript>.*</noscript>##gsi; #added to remove warnings from lyrc.com.ar, maybe should be restricted to lyrc.com.ar ?
	}

	my (%prop,$ul,@urls,@pixbufs,$title,%namedanchors,$li);
	my $iter=$buffer->get_start_iter;
	my @l=split /(<[^>]*>)/s, $data;
	while (defined($_=shift @l))
	{	s/[\r\n]//g;
		s/\s+/ /g;
		s#&nbsp;# #gi;
		s#<br(?: */)?>#\n#gi;
		if ($_ eq '<pre>') {$_="\n".shift(@l)."\n"}
		if (m/^[^<]/) # insert text
		{	if ($ul && $li)
			{	$buffer->insert($iter, (' 'x$ul).' - ');
				$li=0;
			}
			my $text=::decode_html($_);
			if (keys %prop)
			{ my $tag=$buffer->create_tag(undef,%prop);
			  $buffer->insert_with_tags($iter, $text, $tag);
			}
			else	{$buffer->insert($iter, $text);}
		}
		elsif (m#^<(script|style)[ >]#i) {shift @l while @l && $l[0] ne "</$1>"}
		elsif (m#^<ul[ >]#i) {$buffer->insert($iter,"\n");$ul++}
		elsif (m#^<li[ >]#i) {$li=1}
		elsif (m#^<p[ >]#i) {$buffer->insert($iter,"\n");}
		elsif (my ($tag,$p)=m#^<(\w+) (.*)>$#)
		{	my %p;
			#$p{$1}=$3 while $p=~m/(\w+)=(["'])(.+?)\2/sg;
			$p{$1}=$3 while $p=~m/\G\s*(\w+)=(["'])(.*?)\2/gc || $p=~m/\G\s*(\w+)()=(\S+)/gc;
			if ($tag eq 'a')
			{ if	(exists $p{href}) { push @urls,$iter->get_offset,$p{href}; }
			  elsif	(exists $p{name}) { $namedanchors{$p{name}}=$iter->get_offset; }
			}
			elsif ($tag eq 'font' && 0)
				{ if (my $s=$p{size})
				  {	if ($s=~m/^\d+$/) {$prop{scale}=$s*.33}
					elsif ($s=~m/^(-?\d+)$/) {$prop{scale}||=1;$prop{scale}+=$1*.33}
					else {delete $prop{scale};}
					warn "$s => ".($prop{scale}||"")."\n";
				  }
				  else {delete $prop{scale};}
				}
			elsif ($tag=~m/^h(\d)/i)
				{ $prop{scale}=(3,2.5,2,1.5,1.2,1,.66)[$1];
				  $prop{weight}=Gtk2::Pango::PANGO_WEIGHT_BOLD if $1 eq '1';
				}
			elsif ($tag eq 'table') {$buffer->insert($iter,"\n");}
			elsif ($tag eq 'img' && exists $p{src})
			{	my $mark=$buffer->create_mark(undef,$iter,1);
				push @pixbufs,[$mark, $p{src}, (@urls%3==2 ? $urls[-1] : ())];
			}
			if (exists $p{id}) {$namedanchors{$p{id}}=$iter->get_offset;}
		}
		elsif (m#^</(\w+)>$#)
		{	if    ($1 eq 'a')	{push @urls,$iter->get_offset if @urls%3==2;}
			elsif ($1 eq 'u')	{delete $prop{underline};}
			elsif ($1 eq 'b')	{delete $prop{weight};}
			elsif ($1 eq 'i')	{delete $prop{style};}
			elsif ($1 eq 'font')	{delete $prop{scale};}
			elsif ($1=~m/^h(\d)/i)	{delete $prop{scale};delete $prop{weight};$buffer->insert($iter,"\n");}
			elsif ($1 eq 'ul')	{$buffer->insert($iter,"\n");$ul--;}
			elsif ($1 eq 'tr')	{$buffer->insert($iter,"\n");}
			elsif ($1 eq 'li')	{$buffer->insert($iter,"\n");}
			elsif ($1 eq 'p')	{$buffer->insert($iter,"\n");}
			elsif ($1 eq 'div')	{$buffer->insert($iter,"\n");}
		}
		elsif (m#^<(\w+)>$#)
		{	if    ($1 eq 'u')	{$prop{underline}='single';}
			elsif ($1 eq 'b')	{$prop{weight}=Gtk2::Pango::PANGO_WEIGHT_BOLD;}
			elsif ($1 eq 'i')	{$prop{style}='italic';}
			elsif ($1 eq 'title')	{$title=shift @l while $l[0] ne "</$1>"}
		}
	}
	while (@urls)
	{	my ($offs1,$url,$offs2)=splice @urls,0,3;
		my $tag=$buffer->create_tag(undef,foreground => 'blue',underline => 'single');
		if ($url=~m/^#(.*)/)
		{	if (exists $namedanchors{$1}) {$url='#'.$namedanchors{$1};}
			else {next}
		}
		$tag->{url}=$url;
		$buffer->apply_tag($tag,
			$buffer->get_iter_at_offset($offs1),
			$buffer->get_iter_at_offset($offs2));
	}
	for my $url (map $_->[2], grep @$_>2, @pixbufs)
	{	next unless $url=~m/^#(.*)/;
		if (exists $namedanchors{$1}) {$url='#'.$namedanchors{$1};}
		else {$url=undef}
	}

	$self->{pixtoload}=\@pixbufs;
	::IdleDo('8_FetchPix'.$self,100,\&load_pixbuf,$self) if @pixbufs;
	$self->Save_text if $::Options{OPT.'AutoSave'} && $oklyrics && $oklyrics>0;
}

sub load_pixbuf
{	my $self=shift;
	my $ref=shift @{ $self->{pixtoload} };
	return 0 unless $ref;
	my ($mark,$url,$link)=@$ref;
	$self->{waiting}=Simple_http::get_with_cb(url => $self->full_url($url), cache=>1, cb=>
	sub
	{	$self->{waiting}=undef;
		my $loader;
		$loader=::LoadPixData($_[0]) if $_[0];
		if ($loader)
		{	my $buffer=$self->{buffer};
			my $iter=$buffer->get_iter_at_mark($mark);
			$buffer->delete_mark($mark);
			my $offset=$iter->get_offset;
			$buffer->insert_pixbuf($iter,$loader->get_pixbuf);
			if ($link)
			{	my $tag=$buffer->create_tag(undef,foreground => 'blue');
				$tag->{url}=$link;
				$buffer->apply_tag($tag,$buffer->get_iter_at_offset($offset),$iter);
			}
		}
		::IdleDo('8_FetchPix'.$self,100,\&load_pixbuf,$self); #load next
	});
#::IdleDo('8_FetchPix'.$self,100,\&load_pixbuf,$self) unless $self->{waiting};
}

#sub loaded_old #old method, more crude :)
#{	my $self=shift;
#	my $buffer=$self->{buffer};
#	unless ($_[0]) {$buffer->delete($buffer->get_bounds);$buffer->set_text(_"Loading failed.");return;}
#	local $_=$_[0];
#	s/[\r\n]//g;
#	s#<title>.*?</title>##;
#	s#<script .*?</script>##g;
#	s#<a href="([^"]+)">(.*?)</a>#<>$2<>$1<>#g;
#	s#<br(?: /)?>#\n#g;
#	s/<[^>]+>//g;
#	s/^\n+//;
#	s/BADSONG\n+$//;

#	$buffer->delete($buffer->get_bounds);
#	my @l=split /(<>)/,$_;
#	while (defined ($_=shift @l))
#	{	my $iter=($buffer->get_bounds)[1];
#		if ($_ eq '<>')
#		{	my ($text,undef,$url,undef)=splice @l,0,4;
#			my $tag=$buffer->create_tag(undef,foreground => 'blue',underline => 'single');
#			$tag->{url}=$url;
#			$buffer->insert_with_tags($iter, $text, $tag);
#		}
#		else { $buffer->insert($iter, $_);}
#	}
#}

sub scroll_cb	#zoom with ctrl-wheel
{	my ($textview,$event) = @_;
	return 0 unless $event->state >= 'control-mask';
	my $size=\$::Options{OPT.'FontSize'};
	$$size+= $event->direction eq 'up' ? 1 : -1;
	$$size=4 if $$size<4;
	$$size=50 if $$size>50;
	SetFont($textview);
	return 1;
}

sub button_release_cb
{	my ($textview,$event) = @_;
	my $self=::find_ancestor($textview,__PACKAGE__);
	return ::FALSE unless $event->button == 1;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $url=$self->url_at_coords($x,$y);
	$self->load_url($url) if $url;
	return ::FALSE;
}

sub url_at_coords
{	my ($self,$x,$y)=@_;
	my $iter=$self->{textview}->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		if ($tag->{url}=~m/^#(\d+)?/) { $self->scrollto($1) if defined $1; last }
		my $url= $self->full_url( $tag->{url} );
		if ($url=~m#^http://www\.lyrc\.com\.ar/en/add/add\.php\?#) {::openurl($url); return}	#lyrc specific
		return $url;
	}
}

sub scrollto
{	my ($self,$offset)=@_;
	my $iter=$self->{buffer}->get_iter_at_offset($offset);
	$self->{textview}->scroll_to_iter($iter, 0, ::TRUE, 0, .5);
}

sub full_url
{	my ($self,$url)=@_;
	return $url if $url=~m#^http://#;
	my $base=$self->{url};
	if ($url=~m#^/#){$base=~s#^(?:http://)?([^/]+).*$#$1#;}
	else		{$base=~s#[^/]*$##;}
	return $base.$url;
}


sub update_cursor_cb
{	my $textview=$_[0];
	my (undef,$wx,$wy,undef)=$textview->window->get_pointer;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter=$textview->get_iter_at_location($x,$y);
	my $cursor='xterm';
	for my $tag ($iter->get_tags)
	{	next unless $tag->{url};
		$cursor='hand2';
		last;
	}
	return if ($textview->{cursor}||'') eq $cursor;
	$textview->{cursor}=$cursor;
	$textview->get_window('text')->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
}

sub load_file
{	my ($self,$file)=@_;
	my $buffer=$self->{buffer};
	$buffer->delete($buffer->get_bounds);
	my $text=_("Loading failed.");
	if (open my$fh,'<',$file)
	{	local $/=undef; #slurp mode
		$text=<$fh>;
		close $fh;
		if (my $utf8=Encode::decode_utf8($text)) {$text=$utf8}
	}
        $buffer->set_text($text);

	#make the title and artist bigger and bold
	my ($title,$artist)= Songs::Get($self->{ID},qw/title artist/);
	$title='' if $title!~m/\w\w/;
	for ($title,$artist)
	{	if (m/\w\w/) {s#\W+#\\W*#g}
		else {$_=''}
	}
	$artist='(?:by\W+)?'.$artist if $artist;
	if ($text && $text=~m#^\W*($title\W*\n?(?:$artist)?)\W*\n#si)
	{ my $tag=$buffer->create_tag(undef,scale => 1.5,weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	  $buffer->apply_tag($tag,$buffer->get_iter_at_offset($-[0]),$buffer->get_iter_at_offset($+[0]));
	}

	$buffer->set_modified(0);
}

sub Save_text
{	my $self=::find_ancestor($_[0],__PACKAGE__);
	my $win=$self->get_toplevel;
	my $buffer=$self->{buffer};
	my $text= $buffer->get_text($buffer->get_bounds, ::FALSE);
	my $format=$::Options{OPT.'PathFile'};
	my ($path,$file)=::pathfilefromformat( $self->{ID}, $format, undef,1 );
	unless ($path && $file) {::ErrorMessage(_("Error: invalid filename pattern")." : $format",$win); return}
	my $res=::CreateDir($path,$win);
	return unless $res eq 'ok';
	if (open my$fh,'>:utf8',$path.::SLASH.$file)
	{	print $fh $text;
		close $fh;
		$buffer->set_modified(0);
		warn "Saved lyrics in ".$path.::SLASH.$file."\n" if $::debug;
	}
	else {::ErrorMessage(::__x(_("Error saving lyrics in '{file}' :\n{error}"), file => $file, error => $!),$win);}
}

1