# Copyright (C) 2005-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin AUTOSAVE
Autosave
Autosave plugin
=cut


package GMB::Plugin::AUTOSAVE;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_AUTOSAVE_',
};
my $savesub=$::Command{Save}[0];
my $handle;
::SetDefaultOptions(OPT, minutes => 15);

sub Start
{	$handle=Glib::Timeout->add($::Options{OPT.'minutes'}*60000,$savesub);
}
sub Stop
{	Glib::Source->remove($handle);
	$handle=undef;
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $spin=::NewPrefSpinButton(OPT.'minutes',sub
		{ Stop() if $handle; Start();
		},2,0,1,60*24,1,15,_"Save tags/settings every",_"minutes");
	my $button=Gtk2::Button->new(_"Save now");
	$button->signal_connect(clicked => $savesub);
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $spin,$button;
	return $vbox;
}

1