#!/usr/bin/perl
#
use strict;
use warnings;

use Data::Dumper;
use feature 'say';

use File::Copy;

# Path to eac3to
my $eac3to = '/cygdrive/c/utils/video/eac3to/eac3to.exe';

# Demux parameters for eac3to
my $eac3to_demux = '-demux -keepDialnorm';

#path to bdsup2sub
my $bdsup2sub = 'c:\\\\utils\\\\video\\\\BDSup2Sub400.jar';

# path to mkvmerge
my $mkvmerge = '/cygdrive/c/utils/video/mkvtoolnix/mkvmerge.exe';

#Number of titles on disc
my $numTitles = 0;

# Array with title info
my @titles;
#my @titleinfo;

my %langtable = ();

languages();

my $RUN = 1;


if($RUN == 1)
{
	open(LOGFILE, ">", "scriptlog.txt")  || die "Failed to open log: $!\n";
	# Run eac3to to get general info about the disc
	open(RESULT, $eac3to."|") || die "Failed: $!\n";

	# Iterate through what eac3to outputed
	while(<RESULT>)
	{
		#my $string = unpack("H*", $_);  # For debugging
		#print $string."\n";
		
		# Store info about one title
		my %titleinfo;
		
		# Line containing file name, and length
		if($_ =~ m/^\x08+(\d{1,2}\))\s([\w\.\+]+),\s(\d+:\d\d:\d\d).*/)
		{
			$titleinfo{'filename'} = $2;
			$titleinfo{'length'} = $3;
			$titles[$numTitles] = \%titleinfo;
			$numTitles++;
			
		}
		
		# Line containing title name
		if(!$titles[$numTitles-1]{'name'} && $_ =~m/^\x08+ +\"(.*)\"/)
		{
			print "Found title: ".$1."\n";
			$titles[$numTitles-1]{'name'} = $1;
			$titles[$numTitles-1]{'outputname'} = sprintf("%.2d-%s", $numTitles, $1);
			$titles[$numTitles-1]{'outputname'} =~ s/://g;
		}
	}

	close(RESULT);

#Get titleinfo
my $TITLEINFO = 1;

# Demux
my $DEMUX = 1;

#Actually demux
my $TRUEDEMUX = 1;

#Convert subtitles
my $SUBTITLES = 1;

my $MKVMERGE = 1;


print "----- DEMUX and TITLEINFO ------\n";
for(my $i = 0; $i < @titles; $i++)
#for(my $i = 0; $i < 1; $i++)
{
	#Print out what info we got before moving on
	print $titles[$i]{'name'}."\n";
	print $titles[$i]{'filename'}."\n";
	print $titles[$i]{'length'}."\n\n";
	
	if(-e $titles[$i]{'outputname'}.".mkv")
	{
		print "Title allready muxed, skipping.\n";
		next;
	}
	
	if($TITLEINFO == 1)
	{
		## Get more info about title
		my $lasttrack;
		my @vtracks; # Video tracks
		my @atracks; # Audio tracks
		my @subtitles; # Subtitle tracks
		
		# Run eac3to to get info about specific title
		my $cmd = $eac3to.' '.($i+1).'\)';
		print LOGFILE $cmd."\n";  # For debugging
		
		open(RESULT, $cmd."|") || die "Failed: $!\n";
		while(<RESULT>)
		{
			# Get general information about the title. Number of video, audio and sub tracks
#			EVO, 1 video track, 3 audio tracks, 1 subtitle track, 1:32:28
			if($_ =~ m/(\w+),\s(\d+)\svideo.*,\s(\d+)\saudio.*,\s(\d+)\ssubtitle.*,\s(.*)/)
			{
				$titles[$i]{'container'} = $1;
				$titles[$i]{'tracks_video'} = $2;
				$titles[$i]{'tracks_audio'} = $3;
				$titles[$i]{'tracks_sub'} = $4;

			}
			
			#Get the number of chapters
#		1: Chapters, 20 chapters with names
			elsif($_ =~ m/(\d+)\: Chapters, (\d+) chapters(.*)/)
			{
				print "Found chapters:\n".$_."\n";
				$titles[$i]{'chapters'} = $2;
			}
			# Get the languages and description of subtitle tracks.
			#		6: Subtitle (DVD), English
			elsif($_ =~ m/(\d+)\: Subtitle \(DVD\), (\w+)(.*)/)
			{
				print "Found subtitle track:\n".$_."\n";
				my $language = $2;
				my $trackno = $1;
				my $desc = "";
				if($3 =~ m/, \"(.*)\"/)
				{
						$desc = $1;
				}
				my %subt = ( 'trackno' => $trackno, 'language' => $language, 'desc' => $desc);
				#$subtitles[$trackno] = \@subt;
				#say Dumper($subt);
				push (@subtitles, \%subt);
				$lasttrack = \%subt;
			}
			
			# Get information about the video track
#		2: VC-1, 1080p30 /1.001 (16:9)
			elsif($_ =~ m/(\d+)\: (MPEG2|VC-1), (\d+)(i|p)(\d+)/ )
			{
				print "Found video track:\n".$_."\n";
				print "Codec: ".$2."\n";
				print "Resolution: ".$3."\n";
				print "Frame method: ".$4."\n";
				print "\n";
				
				#my @track = ($1, $2, $3, $4);
				my %track = ('trackno' => $1, 'codec' => $2, 'resolution' => $3, 'field' => $4, 'framerate' => $5);
				#push (@vtracks, \@track);
				push (@vtracks, \%track);
				#$vtracks[$1] = \@track;
				$lasttrack = \%track;
				
			}
			# Get information about audio track
#		3: AC3, English, 5.1 channels, 448kbps, 48kHz
#		4: TrueHD, English, 5.1 channels, 48kHz
#		5: AC3, English, 2.0 channels, 256kbps, 48kHz
			#elsif($_ =~ m/(\d+)\: ([\w\-\/]+),(.*)/)
			#elsif($_ =~ m/(\d+)\: (E-AC3|AC3|E-AC3 Surround), (\w*), ([\d\.]+) channels, ([\d]+kbps), ([\d]+kHz), (.*)/)
			elsif($_ =~ m/(\d+)\: (E-AC3|AC3|TrueHD)/)
			{
				print "Found audio track:\n".$_."\n";
				#print $1."\n";
				#my @track = ($1, $2);
				my %track = ('trackno' => $1, 'codec' => $2); #, 'lang' => $3, 'channels' => $4, 'bitrate' => $5, 'samplerate' => $6);
				
				if($_ =~ m/ ([\d\.]+) channels/)
				{
					$track{'channels'} = $1;
				}
				
				if($_ =~ m/ ([\d\.]+kbps)/)
				{
					$track{'bitrate'} = $1;
				}
				
				if($_ =~ m/ ([\d\.]+kHz)/)
				{
					$track{'samplerate'} = $1;
				}
				
				for my $key (keys %langtable)
				{
					if($_ =~ m/$key/i)
					{
						$track{'language'} = $key;
					}
				}
				
				#$atracks[$1] = \@track;
				#push(@atracks, \@track);
		#		say Dumper(\%track);
				push (@atracks, \%track);
				$lasttrack = \%track;
			}
			elsif($_ =~ m/\"(.*)\"/)
			{
				$lasttrack->{'description'} = $1;
				#print "Desc: ".$1."\n";
			}
			else
			{
				print LOGFILE "Not identified:\n".$_."\n";
			}
		}
		close RESULT;
		$titles[$i]{'atracks'} = \@atracks;
		$titles[$i]{'vtracks'} = \@vtracks;
		$titles[$i]{'subtitles'} = \@subtitles;
		
		#say Dumper($titles[$i]);
	}

	print "--------\n\n";

	my $dir = $titles[$i]{'outputname'};
	print $dir."\n";
	mkdir $dir;
	chdir $dir;

	if($DEMUX == 1)
	{
		my $cmd = $eac3to.' .. '.($i+1).'\)'.' '.$eac3to_demux;
		print LOGFILE $cmd."\n";
		if($TRUEDEMUX == 1)
		{
		
			open (RESULT, $cmd."|") || die "Failed: $!\n";
			while(<RESULT>)
			{
				print LOGFILE $_;
				
				# Subtitle file
				if($_ =~ m/([asv])(\d\d) Creating file \"(.*)\"/)
				{
					print "File  ".int($2)." ". $3."\n";
					if($1 eq 'a')
					{
						print "Audio\n";
						$titles[$i]{'atracks'}[findtrack($titles[$i]{'atracks'}, int($2))]{'file'} = $3;
						#$titles[$i]{'atracks'}[int($2)][1] = $3;
						
					}
					elsif($1 eq 's')
					{
						print "Subtitles\n";
#						$titles[$i]{'subtitles'}[int($2)][2] = $3;
						$titles[$i]{'subtitles'}[findtrack($titles[$i]{'subtitles'}, int($2))]{'file'} = $3;

					}
					elsif($1 eq 'v')
					{
						print "Video\n";
						#$titles[$i]{'video_file'} = $3;
#						$titles[$i]{'vtracks'}[int($2)][3] = $3;
						$titles[$i]{'vtracks'}[findtrack($titles[$i]{'vtracks'}, int($2))]{'file'} = $3;
					}
				}
				elsif($_ =~ m/Creating file \"(.*\.txt)\".../)
				{
					print "Chapters file ".$1."\n";
					$titles[$i]{'chapters_file'} = $1;
				}
				elsif($_ =~ m/Subtitle track (\d+) contains (\d+) captions./)
				{
					#print $_."\n";
					my $tr =  int($1);
					my $cnt =  $2;
					$titles[$i]{'subtitles'}[findtrack($titles[$i]{'subtitles'}, $tr)]->{'file'} =~ s/\.sup/, $cnt captions\.sup/;
					#$titles[$i]{'subtitles'}[$tr][2]  =~ s/\.sup/, $cnt captions\.sup/;
				}
			}
			close RESULT;
		}
	}
	
	say Dumper($titles[$i]);
	
	my %title = %{$titles[$i]};
		
	if($SUBTITLES == 1)
	{
			print "\n **** Converting subtitles ****\n";
			#print ${$title{'vtracks'}[1]}[1]."\n";
			my $res = ${$title{'vtracks'}[0]}{'resolution'};
			print "RESOLUTION: ".$res."\n";
			#for(my $sub = 0; $sub < scalar(@{$title{'subtitles'}}); $sub++)
			for(my $sub = 0; $sub < scalar @{$titles[$i]->{'subtitles'}}; $sub++)
			{
				#print $title{'subtitles'}[$sub][2]."\n";
				my $infile = ${$title{'subtitles'}[$sub]}{'file'};
				if(defined $infile)
				{
					#print $infile."\n";
					my $outfile = "c".$infile;
					my $cmd = "java -jar ".$bdsup2sub." \"".$infile."\" \"".$outfile."\" /res:".$res;
					print LOGFILE $cmd."\n";
					system($cmd);
					move($outfile, $infile);
				}
			}
		}
		
	if($MKVMERGE == 1)
	{
			print "\n**** MKVMerge ****\n";
			my $cmd = $mkvmerge;
			$cmd .= " --output \"../".$title{'outputname'}.".mkv\"";
			$cmd .= " --title \"".$title{'name'}."\"";

			# TODO: Find all video tracks
			for(my $t = 0; $t < scalar @{$title{'vtracks'}}; $t++)
			{
				$cmd .= " \"".${$title{'vtracks'}}[$t]{'file'}."\"";
			}

			for(my $t = 0; $t < scalar @{$title{'atracks'}}; $t++)
			{
				my $l;
				if(defined ($l = ${$title{'atracks'}}[$t]{'language'}))
				{
					if(defined $langtable{lc($l)})
					{
						$cmd .= " --language 0:".$langtable{lc($l)};
					}
				}
								
				$cmd .= " --track-name 0:\"";
				if(defined($l = ${$title{'atracks'}}[$t]{'description'}))
				{
					$cmd .= $l.", ";
				}
				
				# TODO: Split up an check for defined values
				$cmd .= ${$title{'atracks'}}[$t]{'codec'}.", ".${$title{'atracks'}}[$t]{'channels'}." channels, ".${$title{'atracks'}}[$t]{'bitrate'}.", ".${$title{'atracks'}}[$t]{'samplerate'}."\"";
				
				$cmd .= " \"".${$title{'atracks'}}[$t]{'file'}."\"";
			}
			
			for(my $t = 0; $t < scalar @{$title{'subtitles'}}; $t++)
			{
				if(not defined ${$title{'subtitles'}}[$t]{'file'} or (length(${$title{'subtitles'}}[$t]{'file'})  < 2))
				{
					next;
				}
				my $l;
				if(defined ($l = ${$title{'subtitles'}}[$t]{'language'}))
				{
					if(defined $langtable{lc($l)})
					{
						$cmd .= " --language 0:".$langtable{lc($l)};
					}
				}
				
				if(defined($l = ${$title{'subtitles'}}[$t]{'desc'}) && (length($l) >0))
				{
					$cmd .= " --track-name 0:\"".$l."\"";
				}

				$cmd .= " \"".${$title{'subtitles'}}[$t]{'file'}."\"";
			}
			
			#print $title{'chapters_file'}."\n";
			if(defined $title{'chapters_file'})
			{
				$cmd .= " --chapters \"".$title{'chapters_file'}."\"";
			}
			
			print LOGFILE $cmd."\n";
			system($cmd);
		}

		chdir '..';	
}

	close LOGFILE;

}

sub findtrack
{
	my($tracks, $track) = @_;
	for(my $t = 0; $t < scalar @{$tracks}; $t++)
	{
		if($track == ${$tracks}[$t]->{'trackno'})
		{
			return $t;
		}
	}
}

sub languages
{
	#open FILE, "<", "langs.txt" or die $!;
	open(FILE, $mkvmerge." --list-languages|") || die "Failed: $!\n";
	my $i = 1;
	while(<FILE>)
	{
		if($_ =~ m/English language name.*/)
		{
			#print "*** Header\n";
		}
		elsif($_ =~ m/^[-\+]+/)
		{
			#print "*** Divider\n";
		}
		#elsif($_ =~ m/([\w;\ \(\),-\.]+)\s*\|\s(\w{3})\s*|\s.*/)
		else
		{
				my ($lang, $code) = split /\s*(?:\||$)\s*/, $_;
				
				if($lang =~ m/;/)
				{
					#print "Multiple\n";
					my @langs = split  /; /, $lang;
					foreach my $l (@langs)
					{
						$langtable{lc($l)} = $code;
					}
					
				}
				else
				{
					$langtable{lc($lang)} = $code;
				}
				#print $1.": ".$2."\n";
				#print $1."\n";
				#print "Language: $lang - $code\n";
		}
		#else
		#{
#			print $i.": ".$_;
		#}
		$i++;
	}
	close FILE;
	
	
	#say Dumper(\%langtable);
#	print $langtable{'english'}."\n";
}
