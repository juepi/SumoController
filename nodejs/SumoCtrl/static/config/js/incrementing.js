$(function() {

  $(".int-row").append('<div class="inc button">+1</div><div class="dec button">-1</div>');
  $(".float-row").append('<div class="inc button">+0.1</div><div class="dec button">-0.1</div>');

  $(".button").on("click", function() {

    var $button = $(this);
    var oldValue = $button.parent().find("input").val();
	var newVal = 0;
	
    if ($button.text() == "+0.1") {
	// Temperatures must be less than 26°C
	if (oldValue < 26) {
        var newVal = (parseFloat(oldValue) + 0.1).toFixed(1);
	    } else {
        newVal = 26;
		}
 	}
	if ($button.text() == "-0.1") {
	   // ..and more than 15°C
      if (oldValue > 15) {
        var newVal = (parseFloat(oldValue) - 0.1).toFixed(1);
	    } else {
        newVal = 15;
		}
	}

    if ($button.text() == "+1") {
      if (oldValue < 23) {
		// Hours must be less than 24
        var newVal = parseFloat(oldValue) + 1;
	    } else {
        newVal = 0;
		}
 	}
	if ($button.text() == "-1") {
	   // ..and ge 0
      if (oldValue > 0) {
        var newVal = parseFloat(oldValue) - 1;
	    } else {
        newVal = 23;
		}
	}

    $button.parent().find("input").val(newVal);

  });

});