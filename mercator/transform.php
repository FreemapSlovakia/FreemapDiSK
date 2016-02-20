<?php

	if ($argc != 3) {
		die('Syntax php transform.php MapFeatures.xml 0.6  (factor)');
	}

//	die($argv[2]);
	$factor = $argv[2];

	function multi_explode($pattern, $string) {
		$Res = array();
		$Tmp = "";
		for ($i = 0; $i < strlen($string); $i++) {
			if (($i+1 < strlen($string)) && ($string[$i] == 'p') && ($string[$i+1] == 'x')) {
				if ($Tmp != "") {
					$Res[] = $Tmp;
					$Tmp = "";
				}
				$Res[] = $string[$i];
			} else {
				if (strpos($pattern, $string[$i]) !== false) {
					if ($Tmp != "") {
						$Res[] = $Tmp;
						$Tmp = "";
					}
					$Res[] = $string[$i];
				}  else {
					$Tmp .= $string[$i];
				}
			}

		}
		if ($Tmp != "") {
			$Res[] = $Tmp;
		}
		return $Res;
	}
	if (!file_exists($argv[1].".old") ) {
		rename ($argv[1], $argv[1].".old");
	}	

	$input = file($argv[1].".old");
	$fp = fopen($argv[1], 'w');
	foreach($input as $Line) {
		// transformacia
		$Line = preg_replace_callback ('|(\s+r\s*=\s*[\'\"])([0-9\.\-]+)(px[\'\"])|', "replace2", $Line);
        $Line = preg_replace_callback ('|(\s+dx\s*=\s*[\'\"])([0-9\.\-]+)(px[\'\"])|', "replace2", $Line);
        $Line = preg_replace_callback ('|(\s+dy\s*=\s*[\'\"])([0-9\.\-]+)(px[\'\"])|', "replace2", $Line);
        $Line = preg_replace_callback ('|(\s+pixel\-offset\s*=\s*[\'\"])([0-9\.\-]+)(px[\'\"])|', "replace2", $Line);
        $Line = preg_replace_callback ('|(\s+x\-multi\-labeling\s*=\s*[\'\"])([0-9\.\-]+)([\'\"])|', "replace2", $Line);
        $Line = preg_replace_callback ('|(\s+x\-line\-spacing\s*=\s*[\'\"])([0-9\.\-]+)([\'\"])|', "replace2", $Line);
        $Line = preg_replace_callback ('|(stroke\-width\s*:\s*)([0-9\.\-]+)(;)|', "replace2", $Line);
        $Line = preg_replace_callback ('|(stroke\-dashoffset\s*:\s*)([0-9\.\-]+)(;)|', "replace2", $Line);
        $Line = preg_replace_callback ('|(stroke\-dashoffset\s*:\s*)([0-9\.\-]+)(px;)|', "replace2", $Line);
        $Line = preg_replace_callback ('|(stroke\-width\s*:\s*)([0-9\.\-]+)(px;)|', "replace2", $Line);
        $Line = preg_replace_callback ('|(font\-size\s*:\s*)([0-9\.\-]+)(;)|', "replace2", $Line);
        $Line = preg_replace_callback ('|(font\-size\s*:\s*)([0-9\.\-]+)(px;)|', "replace2", $Line);


		$Line = preg_replace_callback ('|(stroke\-dasharray\s*:\s*)([0-9\.\-]+)(,)([0-9\.\-]+)(;)|', "replace24", $Line);
        $Line = preg_replace_callback ('|(stroke\-dasharray\s*:\s*)([0-9\.\-]+)(,)([0-9\.\-]+)(,)([0-9\.\-]+)(;)|', "replace246", $Line);
        $Line = preg_replace_callback ('|(stroke\-dasharray\s*:\s*)([0-9\.\-]+)(,)([0-9\.\-]+)(,)([0-9\.\-]+)(,)([0-9\.\-]+)(;)|', "replace2468", $Line);
        $Line = preg_replace_callback ('|(patternTransform\s*=\s*[\'\"]scale\()([0-9\.\-]+)(\)[\'\"])|', "replace2", $Line);
		
        #$Line = preg_replace_callback ('|([\'\"])([0-9\.]+)(px[\'\"])|', "replace2", $Line);
		// spojime a zapiseme
		fwrite($fp, $Line);
	}
	fclose($fp);


function replace_number($match) {
	global $factor;
		if (is_numeric($match)) {
		if (($match * $factor) >3) {
			return(round($match* 1000 * $factor) / 1000);
		} else {
        	return(round($match* 100000 * $factor) / 100000);
        }
	} else {
		return($match);
	}

}

function replace2($matches) {
	return ($matches[1].replace_number($matches[2]).$matches[3]);
}


function replace24($matches) {
    return ($matches[1].replace_number($matches[2]).$matches[3].replace_number($matches[4]).$matches[5]);
}

function replace246($matches) {
    return ($matches[1].replace_number($matches[2]).$matches[3].replace_number($matches[4]).$matches[5].replace_number($matches[6]).$matches[7]);
}

function replace2468($matches) {
    return ($matches[1].replace_number($matches[2]).$matches[3].replace_number($matches[4]).$matches[5].replace_number($matches[6]).$matches[7].replace_number($matches[8]).$matches[9]);
}



